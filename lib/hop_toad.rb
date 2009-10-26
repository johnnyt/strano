require 'hpricot'

module Strano
  class HopToad
    attr_accessor :api_key

    class << self
      def method_missing(method, *args, &block)
        hop_toad.send(method, *args, &block)
      end
      
      def hop_toad
        @hop_toad ||= self.new(HOPTOAD[:api_key], HOPTOAD[:base_url])
      end
    end

    def initialize(api_key, base_url)
      @api_key = api_key
      @base_url = base_url
      @environment_filters = %w(AWS_ACCESS_KEY  AWS_SECRET_ACCESS_KEY AWS_ACCOUNT SSH_AUTH_SOCK)
      yield self if block_given?
    end

    def enironment_filters
      %w(AWS_ACCESS_KEY  AWS_SECRET_ACCESS_KEY AWS_ACCOUNT SSH_AUTH_SOCK) 
    end
    
    def send_hoptoad_notification(exception, env)
      data = {
        :api_key       => api_key,
        :error_class   => exception.class.name,
        :error_message => "#{exception.class.name}: #{exception.message}",
        :backtrace     => exception.backtrace,
        :environment   => env.to_hash
      }

      bad_request = Rack::Request.new(env)

      data[:request] = {
        :params => {'request.path' => bad_request.script_name + bad_request.path_info}.merge(bad_request.params)
      }

      rack_env = ENV['RACK_ENV'] || ENV['RAILS_ENV'] || 'development'
      data[:environment] = clean_hoptoad_environment(ENV.to_hash.merge(env))
      data[:environment][:RAILS_ENV] = rack_env

      data[:session] = {
         :key         => env['rack.session'] || 42,
         :data        => env['rack.session'] || { }
      }

      hoptoad_error_url = ""
      if true || %w(staging production).include?(rack_env)
        hoptoad_error_url = send_to_hoptoad :notice => default_notice_options.merge(data)
      end
      env['hoptoad.notified'] = true

      hoptoad_error_url
    end

    def extract_body(env)
      if io = env['rack.input']
        io.rewind if io.respond_to?(:rewind)
        io.read
      end
    end

    def send_to_hoptoad(data) #:nodoc:
      url = URI.parse("http://hoptoadapp.com:80/notices/")

      Net::HTTP.start(url.host, url.port) do |http|
        headers = {
          'Content-type' => 'application/x-yaml',
          'Accept' => 'text/xml, application/xml'
        }
        http.read_timeout = 5 # seconds
        http.open_timeout = 2 # seconds
        # http.use_ssl = HoptoadNotifier.secure
        response = begin
                     http.post(url.path, clean_non_serializable_data(data).to_yaml, headers)
                   rescue TimeoutError => e
                     logger "Timeout while contacting the Hoptoad server."
                     nil
                   end
        case response
        when Net::HTTPSuccess then
          logger "Hoptoad Success: #{response.class}"
          error_id = (Hpricot(response.body).at("//group-id") || Hpricot(response.body).at("//id")).inner_html
          return error_url(error_id)
        else
          logger "Hoptoad Failure: #{response.class}\n#{response.body if response.respond_to? :body}"
          return nil
        end
      end
    end

    def error_url(error_id)
      "#{@base_url}/errors/#{error_id.to_s}"
    end

    def logger(str)
      puts str if ENV['RACK_DEBUG']
    end

    def default_notice_options #:nodoc:
      {
        :api_key       => api_key,
        :error_message => 'Notification',
        :backtrace     => nil,
        :request       => {},
        :session       => {},
        :environment   => {}
      }
    end

    def clean_non_serializable_data(notice) #:nodoc:
      notice.select{|k,v| serializable?(v) }.inject({}) do |h, pair|
        h[pair.first] = pair.last.is_a?(Hash) ? clean_non_serializable_data(pair.last) : pair.last
        h
      end
    end

    def serializable?(value) #:nodoc:
      value.is_a?(Fixnum) || 
      value.is_a?(Array)  || 
      value.is_a?(String) || 
      value.is_a?(Hash)   || 
      value.is_a?(Bignum)
    end

    def stringify_keys(hash) #:nodoc:
      hash.inject({}) do |h, pair|
        h[pair.first.to_s] = pair.last.is_a?(Hash) ? stringify_keys(pair.last) : pair.last
        h
      end
    end

    def clean_hoptoad_environment(environ) #:nodoc:
      environ.each do |k, v|
        environ[k] = "[FILTERED]" if defined?(environment_filter_keys) && environment_filter_keys.any? do |filter|
          k.to_s.match(/#{filter}/)
        end
      end
    end
  end

end
