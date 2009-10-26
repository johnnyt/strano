# I was originally doing something similar to this, but not nearly as neat.
# This was taken from git://github.com/stjernstrom/capistrano_colors.git
# Many thanks to stjernstrom.

module Capistrano
  class Logger

    COLORS = { 
               :none     => "0",
               :black    => "30",
               :red      => "31",
               :green    => "32",
               :yellow   => "33",
               :blue     => "34",
               :magenta  => "35",
               :cyan     => "36",
               :white    => "37"
            } 

    ATTRIBUTES = {
              :none       => 0,
              :bright     => 1,
              :dim        => 2,
              :underscore => 4,
              :blink      => 5,
              :reverse    => 7,
              :hidden     => 8
            }

    @@color_matchers = []

    class << self
      def color(color_to_use, attribute = :none)
        attr_string = "#{ATTRIBUTES[attribute]};"
        "\e[#{attr_string}#{COLORS[color_to_use]}m"
      end

      def colorize(message, color, attribute, nl = "\n")
        attribute = "#{attribute};" if attribute
        "\e[#{attribute}#{color}m" + message.strip + "\e[0m#{nl}"
      end

      def add_color_matcher( options ) #:nodoc:
        @@color_matchers.push( options )
      end 
    end
    
    alias_method :org_log, :log

    def log(level, message, line_prefix=nil) #:nodoc:
      color = :none
      attribute = nil
      
      # Sort matchers in reverse order so we can break if we found a match.
      @@sorted_color_matchers ||= @@color_matchers.sort_by { |i| -i[:prio] }
      
      @@sorted_color_matchers.each do |filter|
        if (filter[:level] == level || filter[:level].nil?)
          if message =~ filter[:match]
            color = filter[:color]
            attribute = filter[:attribute]
            message = filter[:prepend] + message unless filter[:prepend].nil?
            break
          end
        end
      end

      if color != :hide
        current_color = COLORS[color]
        current_attribute = ATTRIBUTES[attribute]
        line_prefix = colorize(line_prefix.to_s, current_color, current_attribute) unless line_prefix.nil?
        org_log(level, colorize(message, current_color, current_attribute), line_prefix=nil)
      end
    end

    def colorize(*args)
      self.class.colorize(*args)
    end

  end

end
