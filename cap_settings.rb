# =============================================================================
# SITE SPECIFIC SETTINGS
# =============================================================================
set :application, 'awesome_engine'
set :domain,      'clickonhealth.com'
set :sub_domain,  'offers'
set :servers, {
  'production'  => { 'default' => 'awesomeengine' },
  'staging'     => { 'default' => 'kenny' }
}
set :shared_directories, %w[ public/surveys/resources public/assets look_and_feel_zips ]
