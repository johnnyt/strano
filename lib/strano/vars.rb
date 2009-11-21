require 'rubygems'
require 'yaml'
require 'termios'

module Strano

  class Vars
    ENCRYPTED_VARS_FILENAME = 'variables.yml.aes'

    class << self
      attr_writer :config_dir, :defaults

      def filename_for(file, type)
        custom_dir = File.expand_path(File.join(config_dir, %W[ file_templates #{type} #{file} ]))
        default_dir = File.expand_path(File.join(File.dirname(__FILE__), %W[ .. .. file_templates #{type} #{file} ]))
        File.exist?(custom_dir) ? custom_dir : default_dir
      end

      def config_dir
        @config_dir ||= begin
          rails_config_path = File.expand_path(File.join(File.dirname(__FILE__), %w[ .. .. .. .. .. config strano_custom_files ]))

          # Running from within RAILS_ROOT/vendor/plugins/strano
          if File.exists?(rails_config_path)
            config_path = rails_config_path

          # Running from within the strano dir
          else
            config_path = File.join(File.dirname(__FILE__), %w[ .. .. strano_custom_files ])
          end
          File.expand_path(config_path)
        end
      end

      def defaults
        @defaults ||= begin
          filename = File.join(config_dir, 'defaults.yml')
          hash = YAML.load(File.open(filename))
          HashWithIndifferentAccess.new(hash)
        end
      end

      def [](var)
        defaults[var]
      end

      def secure_var(variable_name, &block)
        raise ArgumentError, "please specify a block" unless block
        variable_procs[variable_name] = block
      end

      def variable_procs
        @variable_procs ||= {}
      end

      def variables
        prompt_for_password
        
        plain_text_var_hash = {}

        variable_procs.each do |var_name, var_proc|
          plain_text_var_hash[var_name] = var_proc.call(@encrypted_variables)
        end

        plain_text_var_hash
      end

      def prompt_for_password 
        $stdin.extend Termios
        oldt = $stdin.tcgetattr
        newt = oldt.dup
        newt.lflag &= ~Termios::ECHO
        $stdin.tcsetattr(Termios::TCSANOW, newt)

        begin
          valid_input = false
          while !valid_input
            puts Capistrano::Logger.color(:yellow)
            puts "  Encrypted File Password:".rjust(Strano::RJUST) + Capistrano::Logger.color(:none)

            password = $stdin.gets
            yaml_content = `cat #{File.join(%W[ #{config_dir} #{ENCRYPTED_VARS_FILENAME} ])} | openssl aes-256-cbc -d -salt -k '#{password.chomp}'`

            if $? == 0
              valid_input = true 
            else
              puts Capistrano::Logger.color(:red) + "Incorrect Password! - Try again.".rjust(Strano::RJUST)
            end
          end
        # rescue
        ensure
          $stdin.tcsetattr(Termios::TCSANOW, oldt)
        end

        puts Capistrano::Logger.color(:green)
        puts "  Correct password. File has been decrypted --- Moving along ...#{Capistrano::Logger.color(:none)}\n\n"

        @encrypted_variables = YAML.load(yaml_content)
      end
    end

  end
end
