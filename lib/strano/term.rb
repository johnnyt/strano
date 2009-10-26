module Strano
  
  module Term
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

    def color(color_to_use, attribute = :none)
      attr_string = "#{ATTRIBUTES[attribute]};"
      "\e[#{attr_string}#{COLORS[color_to_use]}m"
    end

    def colorize(message, color, attribute, nl = "\n")
      attribute = "#{attribute};" if attribute
      "\e[#{attribute}#{color}m" + message.strip + "\e[0m#{nl}"
    end
  end

end
