require 'fileutils'
require 'activesupport'
require 'active_record'
require 'action_controller'
require 'action_view'

namespace :sass do
  desc 'Updates stylesheets if necessary from their Sass templates.'
  task :update => :environment do
    Sass::Plugin.update_stylesheets
  end
end

namespace :snapshot do
  desc "Snaphot DB and all shared directories"
  task :create => :environment do
    include ActionView::Helpers::NumberHelper
    start_time = Time.now

    snapshot_type = ENV['SNAPSHOT_TYPE'] || 'quick'

    snapshot_name = Time.now.to_s(:number)
    snapshot_dir = File.join(RAILS_ROOT, 'snapshots', snapshot_name)

    FileUtils.mkdir_p(snapshot_dir)
    FileUtils.chdir(snapshot_dir)

    # DB
    STDERR.puts "Dumping #{RAILS_ENV.to_s.upcase} DB to db.sql"
    config = ActiveRecord::Base.configurations[RAILS_ENV]
    password = config['password'] ? "-p'#{config['password']}'" : ''
    mysql_dump_options = [

        # add-drop-database Add a DROP DATABASE statement before each CREATE DATABASE statement      
        "--add-drop-database",

        # add-drop-table Add a DROP TABLE statement before each CREATE TABLE statement
        "--add-drop-table",

        # compact Produce less verbose output
        "--compact",

        #complete-insert Use complete INSERT statements that include column names
        "--complete-insert",

        # quick Retrieve rows for a table from the server a row at a time
        "--quick",

        # --no-data no-data Do not write any table row information (that is, do not dump table contents, only table definitions)
        # 
        # --where='where_condition' where Dump only rows selected by the given WHERE condition
        # --ignore-table=db_name.tbl_name ignore-table Do not dump the given table
        # 
        # # DO NOT USE THIS:
        # --single-transaction single-transaction This option issues a BEGIN SQL statement before dumping data from the server
        # 
        # 
        # 
        # --no-create-info no-create-info Do not write CREATE TABLE statements that re-create each dumped table      
        # --no-create-db no-create-db This option suppresses the CREATE DATABASE statements      
        # --no-autocommit no-autocommit Enclose the INSERT statements for each dumped table within SET autocommit = 0 and COMMIT statements      
        # --flush-logs flush-logs Flush the MySQL server log files before starting the dump
        # --disable-keys disable-keys For each table, surround the INSERT statements with disable and enable keys statements
        # --create-options create-options Include all MySQL-specific table options in the CREATE TABLE statements
        # 
        # 
        # 
        # tbl_mytable_name –no-data
    ]

    command_no_password = "mysqldump #{mysql_dump_options.join(' ')} -u #{config['username']} {{password}} #{config['database']} > db.sql"
    STDERR.puts "Running: #{command_no_password}"
    `#{command_no_password.gsub("{{password}}", password)}`

    # command = `mysqldump #{mysql_dump_options.join(' ')} -u #{config['username']} #{password} #{config['database']} > db.sql`
    # `#{command}`
    STDERR.puts "    Done - #{number_to_human_size(File.size("db.sql"))}"
    STDERR.puts "Compressing db.sql"
    `tar czf db.tgz db.sql && rm db.sql`
    STDERR.puts "    Done - #{number_to_human_size(File.size("db.tgz"))}"

    # Shared Dirs
    dirs_to_snapshot = []

    # Shared Dirs
    dirs_to_snapshot = []
    if snapshot_type == 'full' && defined?(STRANO_SHARED_DIRS)
      dirs_to_snapshot = STRANO_SHARED_DIRS
    elsif snapshot_type == 'quick' && defined?(STRANO_QUICK_SHARED_DIRS)
      dirs_to_snapshot = STRANO_QUICK_SHARED_DIRS
    end

    unless dirs_to_snapshot.blank?
      dirs_to_snapshot.each do |snapshot_directory|
        dir_filename = snapshot_directory.gsub(%r!/!, '_._')
        command = "tar chzf snapshot_dir_#{dir_filename}.tgz -C #{RAILS_ROOT} #{snapshot_directory}"
        STDERR.puts "Compressing #{snapshot_directory}"
        `#{command}`
        STDERR.puts "    Done - #{number_to_human_size(File.size("snapshot_dir_#{dir_filename}.tgz"))}"
      end
      STDERR.puts "Taring snapshot dirs"
      `tar cf snapshot_dirs.tar snapshot_dir_*.tgz && rm snapshot_dir_*`
      STDERR.puts "    Done - #{number_to_human_size(File.size('snapshot_dirs.tar'))}"
    end

    STDERR.puts "Creating full snapshot"
    `tar cf #{snapshot_name}.tar *`
    FileUtils.mv("#{snapshot_name}.tar", "..")
    FileUtils.cd('..')
    FileUtils.rm_r(snapshot_name)
    FileUtils.rm('current.tar') if File.exist?('current.tar')
    snapshot_filename = "#{snapshot_name}.tar"
    `ln -s #{snapshot_filename} current.tar`
    STDERR.puts "    Done - #{number_to_human_size(File.size(snapshot_filename))}"

    end_time = Time.now
    STDERR.puts "\nDone - took #{(end_time - start_time).to_f / 60.0} minutes"
  end



  desc "Restore DB and all shared directories from current.tar"
  task :restore => :environment do
    include ActionView::Helpers::NumberHelper
    start_time = Time.now

    snapshots_dir = File.expand_path(File.join(RAILS_ROOT, 'snapshots'))
    FileUtils.mkdir_p(snapshots_dir)

    snapshots = Dir.entries(snapshots_dir).sort
    snapshot_file = snapshots.last

    temp_dir = File.join(RAILS_ROOT, %W[ tmp snapshot_#{snapshot_file.gsub(/\.tar/, '')} ])
    FileUtils.mkdir_p(temp_dir)
    FileUtils.chdir(temp_dir)
    STDERR.puts "Untaring main snapshot file to temp dir"
    `tar xf #{snapshots_dir}/#{snapshot_file}`
    STDERR.puts "    Done"

    STDERR.puts "Uncompressing db.tgz"
    `tar xzf db.tgz`
    STDERR.puts "    Done"

    config = ActiveRecord::Base.configurations[RAILS_ENV]
    password = config['password'] ? "-p'#{config['password']}'" : ''

    [
      %Q!DROP DATABASE IF EXISTS #{config['database']}!,
      %Q!CREATE DATABASE #{config['database']}!,
    ].each do |mysql_command|
      `echo "#{mysql_command};" | mysql -u #{config['username']} #{password}`
    end
    command = %Q[mysql -u #{config['username']} #{password} #{config['database']} < db.sql]
    STDERR.puts "Restoring db.sql to #{RAILS_ENV} DB"
    `#{command}`
    STDERR.puts "    Done"

    FileUtils.rm('db.sql')
    FileUtils.rm('db.tgz')

    if File.exist?('snapshot_dirs.tar')
      STDERR.puts "Restoring shared directories"
      snapshot_dirs_dir = File.join(temp_dir, "snapshot_dirs")
      FileUtils.mkdir_p(snapshot_dirs_dir)
      FileUtils.chdir(snapshot_dirs_dir)
      `tar xf ../snapshot_dirs.tar`

      Dir.glob('snapshot_dir_*.tgz').each do |snapshot_dir_tgz|
        # ex: with the directory public/assets/model:
        #    extracted_dir = 'public_._assets_._model'
        extracted_dir = snapshot_dir_tgz.gsub('snapshot_dir_', '').gsub('.tgz', '')

        #    path_to_replace = 'public/assets/model'
        path_to_replace = extracted_dir.gsub('_._', '/')

        #    base_source_dir = 'public/assets'
        base_dirs_array = path_to_replace.split('/')
        base_source_dir = base_dirs_array.length == 1 ? path_to_replace : base_dirs_array[0..-2].join('/')


        STDERR.puts "    #{path_to_replace}"
        FileUtils.mkdir_p(extracted_dir)
        FileUtils.chdir(extracted_dir)
        command = %Q!tar xzf ../#{snapshot_dir_tgz} && rm ../#{snapshot_dir_tgz}!
        `#{command}`

        full_replace_path = File.join(RAILS_ROOT, path_to_replace)

        FileUtils.mkdir_p(full_replace_path)
        FileUtils.rm_r Dir.glob("#{full_replace_path}/*")
        FileUtils.cp_r("#{path_to_replace}/.", full_replace_path)

        FileUtils.chdir('..')
        FileUtils.rm_r(extracted_dir)
        STDERR.puts "        Done"
      end

      FileUtils.rm_r(temp_dir)

      end_time = Time.now
      STDERR.puts "\nDone - took %.2f minutes" % ((end_time - start_time).to_f / 60.to_f)
    end
    
  end
end
