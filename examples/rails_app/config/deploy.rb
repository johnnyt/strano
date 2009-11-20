# =============================================================================
# APPLICATION SPECIFIC SETTINGS
# =============================================================================
set :application, 'strano_example_app'
set :domain,      'yourdomain.com'
set :sub_domain,  'www'
set :servers, {
  'production'  => { 'default' => 'production_server_name' },
  'staging'     => { 'default' => 'pompom' }
}

# These will get zipped up along the DB when snapshots are created / restored.
# set :shared_directories, %w[ public/some_model_with_attachments ]

# =============================================================================
# CUSTOM
# =============================================================================

# These will get removed when app:remove is called
# set :additional_application_files, %w[ /etc/init.d/some_custom_script ]

# Generate all the stylesheets manually (from their Sass templates) before each restart.
# Uncomment this if you are using SASS.
# after 'strano:chown_files', 'sass:update'
