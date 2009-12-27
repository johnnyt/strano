$LOAD_PATH << File.dirname(__FILE__)

require 'capistrano'
require 'active_support'

require 'capistrano_ext/configuration'
require 'capistrano_ext/logger'
require 'capistrano_ext/ssh'
require 'capistrano_ext/error'
require 'capistrano_ext/cli'

require 'strano/term'
require 'strano/vars'
require 'strano/helpers'
require 'strano/strano_file'

require 'strano/rubyinline'

module Strano
  RJUST = 80

  class << self
    def replace(string, b)
      erb_template = string.gsub("{{", "<%=").gsub("}}", "%>")
      ERB.new(erb_template).result(b)
    end
  end
end


Capistrano::Logger.add_color_matcher({ :match => /^sftp upload/,              :color => :cyan,    :level => 1, :prio => -10 })

# DEBUG
Capistrano::Logger.add_color_matcher({ :match => /executing ".*/,             :color => :green,   :level => 2, :prio => -10, :prepend => "== SERVER - " })
Capistrano::Logger.add_color_matcher({ :match => /executing `.*/,             :color => :blue,    :level => 2, :prio => -10, :prepend => "== Cap task: "})
Capistrano::Logger.add_color_matcher({ :match => /.*/,                        :color => :yellow,  :level => 2, :prio => -20 })

# INFO
Capistrano::Logger.add_color_matcher({ :match => /(fatal:|ERROR:).*/,         :color => :red,     :level => 1, :prio => -10 })
Capistrano::Logger.add_color_matcher({ :match => /Permission denied/,         :color => :red,     :level => 1, :prio => -20 })
Capistrano::Logger.add_color_matcher({ :match => /sh: .+: command not found/, :color => :magenta, :level => 1, :prio => -30 })

# IMPORTANT
Capistrano::Logger.add_color_matcher({ :match => /rolling back/,              :color => :red,     :level => 0, :prio => -10 })
Capistrano::Logger.add_color_matcher({ :match => /^err ::/,                   :color => :red,     :level => 0, :prio => -10 })
Capistrano::Logger.add_color_matcher({ :match => /.*/,                        :color => :blue,    :level => 0, :prio => -20 })
