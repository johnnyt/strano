module Capistrano
  class CLI

    def self.colorized_prompt(prompt_string)
      puts %Q!#{Logger.color(:green)}#{'-' * Strano::RJUST}#{Logger.color(:yellow)}!
      input = Capistrano::CLI.ui.ask(prompt_string.rjust(Strano::RJUST) + " ")
      puts Logger::color(:none)
      input
    end

  end
end
