require File.expand_path(File.join(File.dirname(__FILE__), %w[ .. lib strano ]))
require 'tmpdir'

SPHINX_VERSION = "0.9.9-rc2"
SPHINX_PKG_NAME = "0.9.9-rc2"
SPHINX_PKG_VERSION = "r1785"

RUBY_EE_VERSION = "1.8.7"
RUBY_EE_FULL_VERSION = "1.8.7-2010.01"
RUBY_EE_DOWNLOAD_URL = "http://rubyforge.org/frs/download.php/68719/ruby-enterprise-#{RUBY_EE_FULL_VERSION}.tar.gz"

NGINX_VERSION = "0.7.64"


# =============================================================================
# GENERAL SLICE TASKS
# =============================================================================
namespace :slice do
  namespace :password do
    desc "Enters deploy's PW on the server"
    task :deploy do
      sudo "date"
    end
  end

  namespace :nginx do
    desc "Restart NGINX"
    task :restart do
      sudo "/etc/init.d/nginx restart"
    end
  end

  desc "Update ~/.ssh/authorized_keys and reload sshd."
  task :update_keys do
    ssh_dir = "/home/#{deploy_user}/.ssh"
    sudo "mkdir -p #{ssh_dir} && chmod 700 #{ssh_dir} && chown #{deploy_user}:#{deploy_user} #{ssh_dir}"

    put File.read(Strano::Vars.filename_for('authorized_keys.erb', 'slice')), "#{ssh_dir}/authorized_keys", :mode => 0600
    run "chown -R #{deploy_user}:#{deploy_user} #{ssh_dir}"
  end


  desc "Update ~/.ssh/config - automatically adds all servers defined in variables.yml.aes"
  task :update_ssh_config do
    ssh_dir = "/home/#{deploy_user}/.ssh"
    # The dir has been created and proper ownership/permissions have been set - done in the server setup script

    file_template_content = ERB.new(File.read(Strano::Vars.filename_for('ssh_config.erb', 'slice'))).result(binding)

    remote_filename = File.join(ssh_dir, 'config')
    local_filename = File.join(Dir.tmpdir, 'ssh_config')
    current_file_content = ''

    run "if [ ! -e #{remote_filename} ]; then touch #{remote_filename}; fi"
    get remote_filename, local_filename
    current_file_content = File.read(local_filename)

    strano_banner = "## STRANO - DO NOT EDIT BELOW THIS LINE ################################"

    new_file_content = current_file_content.gsub(/^#{strano_banner}.*/m, '')
    new_file_content += strano_banner + "\n\n"
    new_file_content += file_template_content + "\n\n# # # # # # # # # # # # # # # # # # # # # # # # # # # #\n\n"

    servers.keys.each do |server|
      new_file_content += <<DEF
Host #{server}
  User         #{deploy_user}
  Port         #{ssh_options[:port]}
  HostName     #{servers[server]['ip_address']}
  ForwardAgent yes

DEF
    end

    put new_file_content, remote_filename, :mode => 0600
    run "chown -R #{deploy_user}:#{deploy_user} #{ssh_dir}"
  end


  desc "Updates the shell env (.bashrc, .vimrc, etc)"
  task :update_shell_env do
    sudo  %Q!sh -c "mkdir -p /home/#{deploy_user}/.vim/colors && mkdir -p /root/.vim/colors"!

    sudo %Q!chown -R #{deploy_user}:#{deploy_user} /home/#{deploy_user}!

    put render("slice", "start_screen", binding), "/home/#{deploy_user}/start_screen", :mode => 0755
		sudo "mv /home/#{deploy_user}/start_screen /usr/local/bin/"
    put render("slice", "bashrc", binding), "/home/#{deploy_user}/.bashrc"
    put render("slice", "screenrc-#{server_stage}", binding), "/home/#{deploy_user}/.screenrc"
    put render("slice", "vimrc", binding), "/home/#{deploy_user}/.vimrc"
    put render("slice", "rdebugrc", binding), "/home/#{deploy_user}/.rdebugrc"
    put render("slice", "vim_colors.vim", binding), "/home/#{deploy_user}/.vim/colors/vim_colors.vim"

    %w[ .bashrc .vimrc .vim/colors/vim_colors.vim ].each do |file_or_dir|
      sudo  %Q!sh -c "chown -R #{deploy_user}:#{deploy_user} /home/#{deploy_user}/#{file_or_dir} && ! + 
            %Q!cp /home/#{deploy_user}/#{file_or_dir} /root/#{file_or_dir} && ! +
            %Q!chown -R root:root /root/#{file_or_dir}"!
    end
  end


  # =============================================================================
  # SETUP TASKS
  # =============================================================================
  namespace :setup do

    desc "Setup a new slice from scratch (will prompt for temporary root password)."
    task :default do
      start_time = Time.now
      transaction do
        verify_new_slice # Needs input from the user - restart the timer
        start_time = Time.now
        setup_users
        slice.update_shell_env
        slice.update_keys
        slice.update_ssh_config
        setup_script
      end
      num_seconds = Time.now - start_time

      color = server_stage.to_s == 'production' ? Capistrano::Logger.color(:red) : Capistrano::Logger.color(:blue)
      puts "\n\n"
      puts Capistrano::Logger.color(:white) + ("-" * Strano::RJUST)
      puts "#{Capistrano::Logger.color(:green)}Your new server #{Capistrano::Logger.color(:yellow)}#{server_name}#{Capistrano::Logger.color(:green)} was setup in #{Capistrano::Logger.color(:red)}%.2f minutes" % (num_seconds.to_f / 60.0)
      puts Capistrano::Logger.color(:white) + ("-" * Strano::RJUST)
      puts Capistrano::Logger.color(:none)
    end

    desc "[internal] Attempt to login to the slice using default SSH options and root user."
    task :verify_new_slice do
      previous_user = deploy_user
      previous_ssh_options = ssh_options
      set :user, 'root'
      set :ssh_options, {:port => 22, :auth_methods => %w[ password ]}

      valid_pw = false
      while !valid_pw
        begin
          set :temp_root_password, Capistrano::CLI.colorized_prompt("Temp root password: ").chomp
          ssh_options[:password] = temp_root_password
          run 'date'
          valid_pw = true
        rescue Exception => e
          if e.message =~ /Net::SSH::HostKeyMismatch/
            raise "Host Key Mismatch (delete they current entry in your ~/.ssh/known_hosts file)"
          elsif e.message =~ /Net::SSH::AuthenticationFailed: root/
            logger.important e.inspect
            logger.important "Invalid password. Try again."
          else
            raise e
          end
        end
      end

      set :user, previous_user
      set :ssh_options, previous_ssh_options
    end


    desc "[internal] Sets the root password and creates the deploy user"
    task :setup_users do
      on_rollback{ remove_users }
      put render('slice', 'setup_users.sh', binding), 'setup_users.sh', :mode => 0777
      run "./setup_users.sh"
      run "rm setup_users.sh"
    end


    desc "[internal] Removes all users that were setup in setup_users"
    task :remove_users do
      run "if [ -e ~/original_sudoers ]; then cp ~/original_sudoers /etc/sudoers; fi"
      run "chmod 440 /etc/sudoers"
      run %Q!printf "#{temp_root_password}\\n#{temp_root_password}\\n" | passwd!
    end


    desc "[internal] Uploads files and runs script to set up server."
    task :setup_script do
      on_rollback{ rollback_script }

      # Upload all needed files
      put render("slice", "iptables", binding), "iptables.up.rules"
      put render("slice", "nginx.conf", binding), "nginx.conf"
      put render("slice", "nginx_maintenance.include", binding), "nginx_maintenance.include"
      put render("slice", "nginx_init.d", binding), "nginx_init.d"
      put render("slice", "setup.sh", binding), "setup.sh", :mode => 0777

      # TEMP UDEV FIX
      put render("slice", "75-persistent-net-generator.rules", binding), "/etc/udev/rules.d/75-persistent-net-generator.rules"

      run "./setup.sh"
      
      # TEMP UDEV FIX
      run "rm /etc/udev/rules.d/75-persistent-net-generator.rules"

      run "rm setup.sh ~/original_*"
    end

    desc "[internal] Rollback all possible settings from the script"
    task :rollback_script do
      run "if [ -e ~/original_iptables ]; then cp ~/original_iptables /etc/iptables.up.rules && iptables-restore < /etc/iptables.up.rules; fi"
      run "if [ -e ~/original_sshd_config ]; then cp ~/original_sshd_config /etc/ssh/sshd_config && /etc/init.d/ssh reload; fi" 
    end

  end # namespace :setup

  # =============================================================================
  # STATUS TASKS
  # =============================================================================
  namespace :status do
    namespace :passenger do
      desc "Display Passenger memory usage."
      task :memory do
        sudo "passenger-memory-stats"
      end

      desc "Display Passenger status information."
      task :status do
        sudo "passenger-status"
      end
    end
  end

end # namespace :slice


# Needs to be outside of a namespace in order to set a role
desc "[internal] Setup variables used in slice management tasks."
task :setup_slice_variables do
  puts Capistrano::Logger.color(:green) + ("-" * Strano::RJUST)
  Strano::Vars.prompt_for_password

  set :server_name, Capistrano::CLI.colorized_prompt("What is the server's name in variables.yml.aes?")
  raise ArgumentError, "Server Name must be provided" if server_name.blank?

  # =============================================================================
  # PASSWORDS / SECURE VARIABLES
  # =============================================================================
  # Have available to us from previous user input:
  #   server_name
  #   temp_root_password
  Strano::Vars.secure_var(:server_stage)         {|vars| vars['servers'][server_name]['server_stage']}
  Strano::Vars.secure_var(:ip_address)           {|vars| vars['servers'][server_name]['ip_address']}
  Strano::Vars.secure_var(:root_user_password)   {|vars| vars['servers'][server_name]['root_user_password']}
  Strano::Vars.secure_var(:deploy_user_password) {|vars| vars['servers'][server_name]['deploy_user_password']}
  Strano::Vars.secure_var(:mysql_root_password)  {|vars| vars['servers'][server_name]['mysql_root_password']}
  Strano::Vars.secure_var(:servers)              {|vars| vars['servers']}

  # Pull in all needed encrypted variables
	begin
		Strano::Vars.variables.each{ |var, value| set var, value }
	rescue
		puts "ERROR: #{$!.to_s}\nThis is usually due to not having the proper variables setup in variables.yml.aes."
		exit
	end

  role :slice, ip_address

  set :user,        Strano::Vars[:deploy_user]
  set :deploy_user, user
  set :password,    deploy_user_password
  set :runner,      Strano::Vars[:runner_user]
  set :runner_user, runner

  # =============================================================================
  # SSH / SECURITY OPTIONS
  # =============================================================================
  set :ssh_options, Strano::Vars[:ssh_options]
  # set :port,        Strano::Vars[:ssh_options][:port].to_s
  set :use_sudo,    Strano::Vars[:use_sudo]
  default_run_options[:pty] = Strano::Vars[:pty]
end

on :start, 'setup_slice_variables', :only => %w[ slice:password:deploy slice:nginx:restart slice:update_keys slice:update_shell_env slice:update_ssh_config slice:setup ]
