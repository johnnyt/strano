def sed_file(filename, sed_string)
  %Q!
  sed -e '#{sed_string}' #{filename} > #{filename}_new
  mv -f #{filename}_new #{filename}
  chmod 644 #{filename}
  !
end

def _cset(name, *args, &block)
  unless exists?(name)
    set(name, *args, &block)
  end
end

def script_notice_message(message)
  "#{Capistrano::Logger.color(:blue)}--------------------------------------------------------------------------------\\n\\n#{Capistrano::Logger.color(:green)}#{message}\\n\\n#{Capistrano::Logger.color(:none)}"
end

def sudo_rm_if_exists(remote_file_or_dir)
  sudo %Q!sh -c "if [ -e #{remote_file_or_dir} -o -d #{remote_file_or_dir} -o -h #{remote_file_or_dir} ]; then rm -r #{remote_file_or_dir}; fi"!
end

def sudo_rm_if_empty(remote_dir)
  sudo %Q![ -d #{remote_dir} ] && [ $(ls -1 #{remote_dir} | wc -l) == 0 ] && rm -r #{remote_dir}!
rescue
  # Removing the dir failed - we should continue anyway
end

def render(type, file, binding)
  filename = Strano::Vars.filename_for("#{file}.erb", type)
  template = File.read(filename)
  result = ERB.new(template).result(binding)
end

def tail_file(file)
  run "tail -n 200 -f #{shared_path}/log/#{file}" do |channel, stream, data|
    # These lines can be used to tail from multiple servers
    # puts  # for an extra line break before the host name
    # puts "#{channel[:host]}: #{data}" 
    puts data
    break if stream == :err    
  end
end
