# I was originally doing something similar to this, but not nearly as neat.
# This was taken from git://github.com/stjernstrom/capistrano_colors.git
# Many thanks to stjernstrom.

module Capistrano
  class Configuration

    module Variables
      def value_exists?(variable)
        @variables.key?(variable.to_sym) && !@variables[variable].respond_to?(:call)
      end
    end

    # Add custom colormatchers
    #
    # Passing a hash or a array of hashes with custom colormatchers.
    #
    # Add the following to your deploy.rb or in your ~/.caprc
    #
    # == Example:
    #
    #   require 'capistrano_colors'    
    #
    #   capistrano_color_matchers = [
    #     { :match => /command finished/,       :color => :hide,      :prio => 10 },
    #     { :match => /executing command/,      :color => :blue,      :prio => 10, :attribute => :underscore },
    #     { :match => /^transaction: commit$/,  :color => :magenta,   :prio => 10, :attribute => :blink },
    #     { :match => /git/,                    :color => :white,     :prio => 20, :attribute => :reverse },
    #   ]
    #
    #   colorize( capistrano_color_matchers )
    #
    # You can call colorize multiple time with either a hash or an array of hashes multiple times.
    #
    # == Colors:
    #
    # :color can have the following values:
    # 
    # * :hide  (hides the row completely)
    # * :none
    # * :black
    # * :red
    # * :green
    # * :yellow
    # * :blue
    # * :magenta
    # * :cyan
    # * :white
    #
    # == Attributes:
    # 
    # :attribute can have the following values:
    #
    # * :bright
    # * :dim
    # * :underscore
    # * :blink
    # * :reverse
    # * :hidden
    #
    #
    def colorize(options)
      if options.class == Array
        options.each do |opt|
          Capistrano::Logger.add_color_matcher( opt )
        end
      else
        Capistrano::Logger.add_color_matcher( options )
      end
    end
    
  end
end
