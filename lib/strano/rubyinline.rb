# Mainly here so when strano/init.rb gets loaded, the rubyinline fix gets applied.
# (So on the server - we don't create a ton of tmp dirs)
#
# When this file is included a new tmp directory is created
# for ruby-inline which helps to avoid many permission problems.
require 'active_support'
require 'etc'

if !defined?(RAILS_ROOT) && File.dirname(__FILE__) =~ %r</vendor/plugins/strano/>
  RAILS_ROOT = File.expand_path(File.dirname(__FILE__).gsub(%r</vendor/plugins/strano/.*$>, ''))
end

if defined?(RAILS_ROOT)
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
end
