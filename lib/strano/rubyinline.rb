require 'activesupport'
require 'etc'

# Get the app name
RAILS_ROOT = File.dirname(__FILE__).gsub(%r</vendor/plugins/strano/.*$>, '') unless defined?(RAILS_ROOT)
deploy_file = "#{RAILS_ROOT}/config/deploy.rb"
app_name =  if File.file?(deploy_file) && (contents = File.read(deploy_file)) && (contents =~ %r<set\s+:application,\s+['"](\w+)['"]>)
             $1
            elsif RAILS_ROOT =~ %r<^/var/www/(.*)/releases/\d+$>
              $1.gsub(/\W/, '')
            else
              RAILS_ROOT.split('/').last
            end

# Get the user name
uid = Process.uid
username = ""
begin
  username = Etc.getpwuid(uid)['name']
rescue
end
username = uid.to_s if username.blank?

ri_tempdir = "/tmp/ri.#{app_name.underscore}.#{username.underscore}"
Dir.mkdir(ri_tempdir, 0755) unless File.directory?(ri_tempdir)
ENV['INLINEDIR'] = ri_tempdir
