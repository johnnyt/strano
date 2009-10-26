# Capistrano::Configuration.instance.load do
  # =============================================================================
  # CAPISTRANO UI
  # =============================================================================
  namespace :ui do
    desc "[internal] Clear the 'Are you sure?' warning. This is mainly needed so it won't be triggered during a rollback"
    task :clear_warning do
      set :needs_warning, false
    end

    desc "[internal] Are you sure????"
    task :are_you_sure, :once => true do
      _cset(:needs_warning, true)
      if needs_warning
        top_task = task_call_frames.first[:task]
        _cset(:task_name, top_task.fully_qualified_name)
        _cset(:warning_message, top_task.brief_description)

        color = Capistrano::Logger.color(:yellow)
        additional_message =  if exists?(:stage)
          highlight = (stage == 'production') ? Capistrano::Logger.color(:red) : Capistrano::Logger.color(:blue)
          %Q!#{color}    Environment: #{highlight}#{stage.to_s.upcase}#{color} ( #{Capistrano::Logger.color(:blue)}#{server_name}#{color} )\n! +
          %Q!#{color}    Application: #{highlight}#{application}#{color} ( #{Capistrano::Logger.color(:blue)}#{sub_domain}.#{domain}#{color} )!
        else
          %Q!#{color}  Slice:       #{Capistrano::Logger.color(:blue)}#{stage.to_s.upcase}#{color}!
        end

#  #{Capistrano::Logger.color(:yellow)}  Task:        #{Capistrano::Logger.color(:red)}#{task_name}
#  #{Capistrano::Logger.color(:yellow)}  Action:      #{Capistrano::Logger.color(:red)}#{warning_message}

        puts <<-BANNER
  #{Capistrano::Logger.color(:green)} --------------------------------------------------------------------------
  #{Capistrano::Logger.color(:yellow)}  You are about to run a task that #{Capistrano::Logger.color(:cyan)}WILL NOT BE ABLE TO BE UNDONE!

#{additional_message}


  #{Capistrano::Logger.color(:red)}  SERIOUSLY - MAKE SURE THAT:
    1) YOU KNOW WHAT YOU'RE DOING AND
    2) YOU WANT TO PROCEED
  #{Capistrano::Logger.color(:green)}--------------------------------------------------------------------------
  #{Capistrano::Logger.color(:none)}

        BANNER

        valid_input = false
        while !valid_input
          rand_letter = (rand(122-97) + 97).chr
          entered_letter = Capistrano::CLI.ui.ask "Enter the letter '#{Capistrano::Logger.color(:green)}#{rand_letter}#{Capistrano::Logger.color(:none)}' to continue: "
          valid_input = true if rand_letter.downcase == entered_letter.strip.downcase
        end

        puts <<-MOVE_ALONG

  #{Capistrano::Logger.color(:green)}--------------------------------------------------------------------------
  #{Capistrano::Logger.color(:yellow)}  OK - Moving along ...
  #{Capistrano::Logger.color(:green)}--------------------------------------------------------------------------#{Capistrano::Logger.color(:none)}

        MOVE_ALONG

        set :needs_warning, false
      end
    end
  end

# end
