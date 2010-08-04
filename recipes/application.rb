require File.expand_path(File.join(File.dirname(__FILE__), %w[ .. lib strano ]))

set :default_stage, 'staging'
set :stages, %w[ production staging ]
require 'capistrano/ext/multistage'

require 'active_support'

namespace :password do
  desc "Enters deploy's PW on the server"
  task :deploy do
    sudo "date"
  end
end

namespace :maint do
  desc "Put up the maintenance page"
  task :on do
    on_rollback{ maint.off }
    run "if [ -e #{current_path}/public/maintenance-OFF.html ]; then mv #{current_path}/public/maintenance-OFF.html #{current_path}/public/maintenance.html; fi"
  end
  before 'deploy:symlink', 'maint:on'
  before 'deploy:migrate', 'maint:on'

  desc "Take down the maintenance page"
  task :off do
    run "if [ -e #{current_path}/public/maintenance.html ]; then mv #{current_path}/public/maintenance.html #{current_path}/public/maintenance-OFF.html; fi"
  end

  # Don't need an after callback - the maintenance page doesn't exist in this new directory
  after 'deploy:restart', 'maint:off'
end

namespace :snapshot do
  desc "Restores the app from the most recent backup in the remote /backups dir, and sets up the correct permissions on the files."
  task :restore, :roles => :app do
    run "cd #{current_path} && rake snapshot:restore"
    strano.chown_files
  end

  namespace :to do
    desc "Local"
    task :local, :roles => :app do
      filename = "snapshots/current.tar"

      strano_file = StranoFile.new
      download("#{current_path}/#{filename}", filename, :via => :scp) do |channel, name, received, total|
        strano_file.update(:name => name, :total_size => total, :received => received)
        STDERR.puts strano_file.full_message
      end
      puts strano_file.completed_message

      `rake snapshot:restore`
    end

    desc "Staging"
    task :staging, :roles => :app do
      start_time = Time.now

      source_stage = "production"
      
      color = Capistrano::Logger.color(:blue)
      no_color = Capistrano::Logger.color(:none)
      server_name_colors = {
        :source => ((source_stage == 'production') ? Capistrano::Logger.color(:red) : Capistrano::Logger.color(:yellow)),
        :destination => ((stage == 'production') ? Capistrano::Logger.color(:red) : Capistrano::Logger.color(:yellow))
      }

      source_string = "#{server_name_colors[:source]}#{servers[source_stage]['default']}: #{no_color}"
      destination_string = "#{server_name_colors[:destination]}#{servers[stage]['default']}: #{no_color}"

      command = "cd /home/#{deploy_user}/#{application}/ && rake snapshot:create"
      puts %Q!       #{source_string}#{color}Running: "#{command}"#{no_color}!
      remote_connection = Net::SSH.start(servers[source_stage]['default'], deploy_user)
      remote_connection.exec!(command)

      source = "#{servers[source_stage]['default']}:/home/#{deploy_user}/#{application}/snapshots/current.tar"
      command = "scp #{source} #{current_path}/snapshots/current.tar"
      puts %Q!       #{destination_string}#{color}Running: "#{command}"#{no_color}!
      run command

      command = "cd /home/#{deploy_user}/#{application}/ && rake snapshot:restore"
      puts %Q!       #{destination_string}#{color}Running: "#{command}"#{no_color}!
      run command

      puts %Q!        #{color}Done. (took #{(Time.now - start_time).to_f / 60.0} minutes)#{no_color}!
    end
  end
end


# =============================================================================
# APPLICATION TASKS (setup, remove, restart)
# =============================================================================
namespace :app do
  desc "Setup the site on a server (deploy:setup, DB, config files, initial code checkout)"
  task :setup, :roles => :app do
    transaction do
      deploy.setup
      setup_initial_files_and_paths
      db.setup
    end

    deploy.update
  end


  desc "[internal] Sets up all shared config files (database.yml, any additional config files, etc)"
  task :setup_initial_files_and_paths, :roles => :app do
    # If this task fails - we should rollback the entire app:setup process (remove the site from the server)
    on_rollback { app.remove_all_files }

    # So tasks such as consumer:restart know not to run when setting up the app
    set :initial_app_setup, true

    # The entire app should default to deploy:deploy (the deploy:setup task runs as root)
    sudo "chown -R #{deploy_user}:#{deploy_user} #{base_path}"
    sudo "chmod -R 775 #{base_path}"

    sudo "chown -R #{runner_user}:#{deploy_user} #{shared_path}"
    sudo "chmod -R 775 #{shared_path}"

    %w[ config log backups snapshots tmp ].each do |dir|
      run "mkdir -p #{shared_path}/#{dir}"
    end

    put render('application', 'database.yml', binding), "#{shared_path}/config/database.yml"
    put render('application', 'my.cnf', binding), "#{shared_path}/my.cnf"

    put ERB.new(File.read(Strano::Vars.filename_for("nginx_vhost_#{stage}.erb", 'application'))).result(binding), "nginx-#{domain}-#{sub_domain}"
    sudo "mv nginx-#{domain}-#{sub_domain} /etc/nginx/sites-available/#{domain}-#{sub_domain}"

    if exists?(:additional_config_files)
      additional_config_files.each do |filename, erb_template|
        dest_path = "#{shared_path}/config/#{Strano.replace(filename, binding)}"
        put ERB.new(erb_template).result(binding), dest_path #, :mode => 0440
        sudo "chmod 0440 #{dest_path}"
      end
    end

    # Create link for easier use of the application when sshing in
    run "if [ -h /home/#{deploy_user}/#{application} ]; then rm /home/#{deploy_user}/#{application}; fi"
    run "ln -s #{current_path} /home/#{deploy_user}/#{application}"
  end


  desc "[internal] Link shared files to current release."
  task :link_files, :roles => [:app] do
    %w[ tmp snapshots backups ].each do |dir|
      run "if [ -e #{current_release}/#{dir} ]; then rm -r #{current_release}/#{dir}; fi"
      run "mkdir -p #{shared_path}/#{dir}"
      run "ln -nsf #{shared_path}/#{dir} #{current_release}/#{dir}"
    end

    run "ln -nsf #{shared_path}/config/database.yml #{current_release}/config/database.yml"
    run "ln -nsf #{shared_path}/my.cnf #{current_release}/.my.cnf"

    if exists?(:additional_config_files)
      additional_config_files.each do |filename, erb_template|
        run "ln -nsf #{shared_path}/config/#{Strano.replace(filename, binding)} #{current_release}/config/#{Strano.replace(filename, binding)}"
      end
    end

    if exists?(:shared_directories)
      shared_directories.each do |sd|
        sudo "mkdir -p #{shared_path}/#{sd}"
        run "if [ -h #{current_release}/#{sd} ]; then rm #{current_release}/#{sd}; fi"
        run "ln -nsf #{shared_path}/#{sd} #{current_release}/#{sd}"
      end
    end
  end
  after "deploy:update_code", "app:link_files"


  desc "[internal] Set up all the correct permissions for files."
  task :chown_files, :roles => [:app] do
    sudo "chown -R #{runner_user}:#{deploy_user} #{shared_path}"
    sudo "chmod -R 775 #{shared_path}"

    sudo "chown #{runner_user}:#{runner_user} #{current_release}/config/environment.rb"
  end
  after "app:link_files", "app:chown_files"
  after "deploy:migrate", "app:chown_files"


  desc "[internal] Removes all remote files from the server (application directory)."
  task :remove_all_files, :roles => :app do
    files_to_remove = %W[
      #{base_path}
      /etc/nginx/sites-available/#{domain}-#{sub_domain}
      /etc/nginx/sites-enabled/#{domain}-#{sub_domain}
      /home/#{deploy_user}/#{application}
    ]

    files_to_remove += additional_application_files if exists?(:additional_application_files)
    
    files_to_remove.each do |file|
      sudo_rm_if_exists(file)
    end
    
    sudo_rm_if_empty(File.expand_path(File.join(base_path, '..')))

    nginx.restart
  end


  desc "[internal] Remove the application from the server (db, files, etc)"
  task :remove, :roles => [:db, :app] do
    app.remove_all_files
    db.drop
  end

end


# =============================================================================
# TAILING FILES
# =============================================================================
namespace :tail do
  desc "Tail rails log."
  task :rails do
    tail_file('production.log')
  end
end


# =============================================================================
# DB
# =============================================================================
namespace :db do
  desc "[internal] Drop mysql user and database."
  task :drop, :roles => :db do
    on_rollback { db.remove_vars }
    [
      %Q!DROP DATABASE IF EXISTS #{db_name}!,
    ].each do |mysql_command|
      run %Q!echo "#{mysql_command};" | mysql!
    end
  end

  desc "[internal] Create mysql user and database."
  task :setup, :roles => :db do
    on_rollback { db.remove_vars }
    [
      %Q!DROP DATABASE IF EXISTS #{db_name}!,
      %Q!CREATE DATABASE #{db_name}!,
      %Q!GRANT ALL PRIVILEGES ON #{db_name}.* TO '#{db_user}'@'localhost' IDENTIFIED BY '#{db_password}'!
    ].each do |mysql_command|
      run %Q!echo "#{mysql_command};" | mysql!
    end
  end

  desc "[internal] Setup the mysql user and password in .my.cnf"
  task :setup_vars, :roles => :db do
    put render("slice", "my.cnf", binding), "/home/#{deploy_user}/.my.cnf", :mode => 0640
  end

  desc "[internal] Removes the .my.cnf (no peeping allowed :)"
  task :remove_vars, :roles => :db do
    %w[ my.cnf .my.cnf ].each {|f| run %Q!if [ -f #{f} ]; then rm -f #{f}; fi!}
  end

  on :before, 'db:setup_vars', :only => %w[ db:drop db:setup ]
  on :after,  'db:remove_vars', :only => %w[ db:drop db:setup ]
end


# =============================================================================
# DEPLOY (includes overrides due to Passenger)
# =============================================================================
namespace :deploy do
  desc "Restarting Passenger with restart.txt"
  task :restart, :roles => :app, :except => { :no_release => true } do
    sudo "touch #{current_path}/tmp/restart.txt", :as => 'www-data'
  end

  [:start, :stop].each do |t|
    desc "[internal] #{t} task is a no-op with Passenger"
    task t, :roles => :app do ; end
  end
end

namespace :multistage do
  desc "[internal] No-op (using simplified multi-stage configuration)"
  task :prepare do ; end
end


# =============================================================================
# SASS
# =============================================================================
namespace :sass do
  desc 'Updates the stylesheets generated by Sass'
  task :update, :roles => :app do
    run "mkdir -p #{current_release}/public/stylesheets"
    sudo "chown -R #{runner_user}:#{deploy_user} #{current_release}/public/stylesheets"
    run "cd #{current_release}; rake sass:update --trace"
  end
end


# =============================================================================
# NGINX
# =============================================================================
namespace :nginx do
  desc "Enable the site on the NGINX level"
  task :enable, :roles => :app do
    sudo_rm_if_exists("/etc/nginx/sites-enabled/#{domain}-#{sub_domain}")
    sudo "ln -s /etc/nginx/sites-available/#{domain}-#{sub_domain} /etc/nginx/sites-enabled/#{domain}-#{sub_domain}"
    nginx.restart
  end

  desc "Disable the site on the NGINX level"
  task :disable, :roles => :app do
    sudo_rm_if_exists("/etc/nginx/sites-enabled/#{domain}-#{sub_domain}")
    nginx.restart
  end

  desc "Restart NGINX"
  task :restart, :roles => :app do
    sudo "/etc/init.d/nginx restart"
  end
end



# =============================================================================
# STAGES
# =============================================================================
desc "Set the target stage to 'staging'."
task :staging do 
  set :stage, 'staging'
  set :rails_env, 'staging'
end 

desc "Set the target stage to 'production'."
task :production do 
  set :stage, 'production'
  set :rails_env, 'production'
end 

# =============================================================================
# CAPISTRANO UI
# =============================================================================
namespace :ui do
  desc "[internal] Announce the stage."
  task :announce_stage do
    if exists?(:stage)
      color = stage.to_s == 'production' ? Capistrano::Logger.color(:red) : Capistrano::Logger.color(:blue)
      server_name = servers[stage].kind_of?(Hash) ? servers[stage]['default'] : servers[stage].to_s

      puts Capistrano::Logger.color(:green) + ("-" * Strano::RJUST)
      puts color + stage.to_s.rjust(Strano::RJUST)
      puts server_name.rjust(Strano::RJUST)
      puts Capistrano::Logger.color(:green) + ("-" * Strano::RJUST)
      puts Capistrano::Logger.color(:none)
    end
  end
end


desc "[internal] Setup variables used in all tasks."
task :setup_application_variables do
  set :server_name, servers[stage].kind_of?(Hash) ? servers[stage]['default'] : servers[stage].to_s

  # Have available to us from deploy.rb / stage task:
  #   application
  #   domain
  #   sub_domain
  #   servers
  #   server_name

  # SERVERS
	# Right now - Strano has only been tested with everything running on the same server.
	# It would be nice to be able to use different servers for each role.
	[ :web, :app, :files, :db ].each do |server_role|
		role server_role, server_name, :primary => true
	end


  set :port,        Strano::Vars[:ssh_options][:port].to_s
  set :user,        Strano::Vars[:deploy_user]
  set :deploy_user, Strano::Vars[:deploy_user]
  set :runner,      Strano::Vars[:runner_user]
  set :runner_user, runner

  Strano::Vars.secure_var(:password)             {|vars| vars['servers'][server_name]['deploy_user_password']}
  Strano::Vars.secure_var(:mysql_root_password)  {|vars| vars['servers'][server_name]['mysql_root_password']}

  # DATABASE VARIALBES
  set :db_name, "#{application}_#{stage}"
  set :db_user, application[0...16] # MySQL usernames must be 16 chars or less
  Strano::Vars.secure_var(:db_password) {|vars| vars['applications'][application][stage]['mysql_password']}

  # Pull in all needed encrypted variables
  Strano::Vars.variables.each {|var, value| set var, value}

  
  # SOURCE CONTROL
  set :scm,               :git
  set :deploy_via,        :remote_cache
  set :repository_cache,  'git_cache'
  set :repository,        Strano.replace(Strano::Vars[:scm][:repository], binding) unless value_exists?(:repository)
  set :deploy_to,         Strano.replace(Strano::Vars[:scm][:deploy_to], binding) unless value_exists?(:deploy_to)
  set :keep_releases,     Strano::Vars[:scm][:keep_releases] || 10
  set :branch,            stage unless value_exists?(:branch)
  set :base_path,         File.expand_path(File.join(shared_path, '..'))
end

on :start, 'ui:announce_stage', :setup_application_variables, :except => stages + %w[ 
  multistage:prepare ui:are_you_sure ui:announce_stage
  slice:nginx:restart slice:update_keys slice:update_shell_env slice:update_ssh_config slice:setup
] + stages.map{ |s| "to:#{s}" } + stages.map{ |s| "from:#{s}" }

after 'deploy:symlink', 'deploy:cleanup'
