module Capistrano
  class RemoteError < Error
    def initialize(message)
      super("#{Capistrano::Logger.color(:red)}#{message}#{Capistrano::Logger.color(:none)}")
    end
  end
end
