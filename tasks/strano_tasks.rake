require 'active_support'
require 'fileutils'
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

    snapshot_name = start_time.strftime("%Y%m%d%H%M%S")
    snapshot_dir = File.join(RAILS_ROOT, 'snapshots', snapshot_name)

    STDERR.puts "\n\n-----[ #{start_time.to_s(:db)} | Snapshot #{snapshot_name} | Starting  ]----------------------------------------------------------------------------------\n\n"

    FileUtils.mkdir_p(snapshot_dir)
    FileUtils.chdir(snapshot_dir)

    # DB
    config_keys = []
    config_dbs = []
    ActiveRecord::Base.configurations.each do |k,v|
      config_keys << k
      config_dbs << v['database']
    end
    dbs_to_dump = [ RAILS_ENV ]

    env_dbs = ENV['DBS']
    not_env_dbs = ENV['NOT_DBS']

    env_only_dbs = config_keys.select{ |k| (k =~ %r<#{RAILS_ENV}>) }

    if !env_dbs.blank?
      case env_dbs.downcase
      when 'all'
        dbs_to_dump = config_keys
        # STDERR.puts "  All configs from database.yml: #{dbs_to_dump.join(', ')}"

      when 'env'
        dbs_to_dump = config_keys.select{ |k| (k =~ %r<#{RAILS_ENV}>) }
        # STDERR.puts "  #{RAILS_ENV} only from database.yml: #{dbs_to_dump.join(', ')}"

      else
        STDERR.puts "  Paovided DB list: #{env_dbs}"
        dbs_to_dump = []

        env_dbs.split(',').each do |db_name|
          db_name = RAILS_ENV if db_name == 'env'
          dbs_to_dump += env_only_dbs.select{ |k| k =~ %r<#{db_name}> }
          # dbs_to_dump += config_keys.select{ |k| k =~ %r<#{db_name}> }
        end
      end

    elsif !not_env_dbs.blank?
      initial_dbs = config_keys.select{ |k| (k =~ %r<#{RAILS_ENV}>) }
      dbs_not_to_dump = []

      not_env_dbs.split(',').each do |db_name|
        dbs_not_to_dump += config_keys.select{ |k| k =~ %r<#{db_name}> }
      end

      dbs_to_dump = initial_dbs - dbs_not_to_dump

      # STDERR.puts "  Provided NOT_DBS=#{not_env_dbs} - These will be dumped: #{dbs_to_dump.join(', ')}"
    end

    dbs_to_dump.uniq!

    if dbs_to_dump.blank?
      STDERR.puts "No matching DBs - defaulting to #{RAILS_ENV}"
      dbs_to_dump = [ RAILS_ENV ]
    end

    STDERR.puts "\nDumping DBs: #{dbs_to_dump.join(', ')}\n\n"
    dbs_to_dump.each do |db_name|
      rails_env_filename = db_name.gsub(RAILS_ENV, "rails_env")
      raw_filename = "db_#{rails_env_filename}.sql"
      tgz_filename = "db_#{rails_env_filename}.tgz"
      STDERR.puts %Q!

- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Dumping '#{db_name}' to #{raw_filename}

!

      config = ActiveRecord::Base.configurations[db_name]
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

      command_no_password = "mysqldump #{mysql_dump_options.join(' ')} -u #{config['username']} {{password}} #{config['database']} > #{raw_filename}"
      STDERR.puts "  Running: #{command_no_password}"
      `#{command_no_password.gsub("{{password}}", password)}`

      STDERR.puts "       Raw SQL file size:    #{number_to_human_size(File.size(raw_filename))}"
      STDERR.puts "   Compressing SQL dump file"
      `tar czf #{tgz_filename} #{raw_filename} && rm #{raw_filename}`
      STDERR.puts "       Compressed file size: #{number_to_human_size(File.size(tgz_filename))}\n"
    end

    STDERR.puts %Q!
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Done dumping DBs

!

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
        STDERR.puts "       Compressed file size: #{number_to_human_size(File.size("snapshot_dir_#{dir_filename}.tgz"))}"
      end
      STDERR.puts "Taring snapshot dirs"
      `tar cf snapshot_dirs.tar snapshot_dir_*.tgz && rm snapshot_dir_*`
      STDERR.puts "       Compressed file size: #{number_to_human_size(File.size("snapshot_dirs.tar"))}"
    end

    STDERR.puts "Creating full snapshot"
    `tar cf #{snapshot_name}.tar *`
    FileUtils.mv("#{snapshot_name}.tar", "..")
    FileUtils.cd('..')
    FileUtils.rm_r(snapshot_name)
    FileUtils.rm('current.tar') if File.exist?('current.tar')
    snapshot_filename = "#{snapshot_name}.tar"
    `ln -s #{snapshot_filename} current.tar`
    STDERR.puts "       Compressed file size: #{number_to_human_size(File.size(snapshot_filename))}"

    end_time = Time.now
    STDERR.puts "\n\n       snapshots/#{snapshot_filename} #{number_to_human_size(File.size(snapshot_filename))}"
    STDERR.puts "\n\n-----[ #{end_time.to_s(:db)} | Snapshot #{snapshot_name} | Completed - took %.2f minutes ]-----\n\n" % ((end_time - start_time).to_f / 60.0)
  end



  desc "Restore DB and all shared directories from current.tar"
  task :restore => :environment do
    include ActionView::Helpers::NumberHelper
    start_time = Time.now

    snapshots_dir = File.expand_path(File.join(RAILS_ROOT, 'snapshots'))
    FileUtils.mkdir_p(snapshots_dir)

    FileUtils.chdir(snapshots_dir)
    snapshots = Dir.glob("*.tar").sort

    if snapshots.blank?
      STDERR.puts "\n\nNo Snapshot to restore from was found in #{shapshots_dir} - nothing to do."
      return
    end

    snapshot_file = snapshots.last
    snapshot_name = snapshot_file.gsub(/\.tar$/, '')

    STDERR.puts "\n\n-----[ #{start_time.to_s(:db)} | Restoring #{snapshot_name} | Starting  ]----------------------------------------------------------------------------------\n\n"

    temp_dir = File.join(RAILS_ROOT, %W[ tmp snapshot_#{snapshot_name} ])
    FileUtils.mkdir_p(temp_dir)
    FileUtils.chdir(temp_dir)
    STDERR.puts "Untaring main snapshot file to temp dir"
    `tar xf #{snapshots_dir}/#{snapshot_file}`
    STDERR.puts "    Done"

    config_keys = []
    config_dbs = []
    ActiveRecord::Base.configurations.each do |k,v|
      config_keys << k
      config_dbs << v['database']
    end

    db_files = Dir["./db_*"]
    db_files.each do |db_file|
      if db_file =~ %r<db_(.*)\.tgz>
        db_name = $1
        ar_db_name = db_name.gsub("rails_env", RAILS_ENV)
        raw_filename = "db_#{db_name}.sql"
        tgz_filename = "db_#{db_name}.tgz"

        if (config = ActiveRecord::Base.configurations[ar_db_name]).blank?
          STDERR.puts " No entry in database.yml for #{ar_db_name}"
          next
        end

        STDERR.puts "Uncompressing #{db_file}"
        `tar xzf #{db_file}`
        STDERR.puts "    Done"

        password = config['password'] ? "-p'#{config['password']}'" : ''

        [
          %Q!DROP DATABASE IF EXISTS #{config['database']}!,
          %Q!CREATE DATABASE #{config['database']}!,
        ].each do |mysql_command|
          `echo "#{mysql_command};" | mysql -u #{config['username']} #{password}`
        end
        command = %Q[mysql -u #{config['username']} #{password} #{config['database']} < #{raw_filename}]
        STDERR.puts "Restoring #{raw_filename} to #{ar_db_name} DB"
        `#{command}`
        STDERR.puts "    Done"

        FileUtils.rm(raw_filename)
        FileUtils.rm(tgz_filename)
      end
    end

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
    end

    end_time = Time.now

    STDERR.puts "\n\n-----[ #{end_time.to_s(:db)} | Restoring #{snapshot_name} | Completed - took %.2f minutes ]-----\n\n" % ((end_time - start_time).to_f / 60.0)
  end
end
