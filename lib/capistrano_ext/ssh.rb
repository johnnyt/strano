module Capistrano
  class SSH
    # Allow for use of options[:ssh_options][:password] correctly - it needs to be set
    # the first time through the begin block if the method is password
    def self.connection_strategy(server, options={}, &block)
      methods = [ %w(publickey hostbased), %w(password keyboard-interactive) ]
      password_value ||= options[:ssh_options][:password]

      ssh_options = (server.options[:ssh_options] || {}).merge(options[:ssh_options] || {})
      user        = server.user || options[:user] || ssh_options[:username] || ServerDefinition.default_user
      port        = server.port || options[:port] || ssh_options[:port]

      ssh_options[:port] = port if port
      ssh_options.delete(:username)

      begin
        connection_options = ssh_options.merge(
          :password => password_value,
          :auth_methods => ssh_options[:auth_methods] || methods.shift
        )

        yield server.host, user, connection_options
      rescue Net::SSH::AuthenticationFailed
        raise if methods.empty? || ssh_options[:auth_methods]
        password_value = options[:password]
        retry
      end
    end
  end
end
