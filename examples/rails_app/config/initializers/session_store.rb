# Be sure to restart your server when you modify this file.

# Your secret key for verifying cookie session data integrity.
# If you change this key, all old sessions will become invalid!
# Make sure the secret is at least 30 characters and all random, 
# no regular words or you'll be exposed to dictionary attacks.
ActionController::Base.session = {
  :key         => '_rails_app_session',
  :secret      => '8e17fba141157fd5ea12eb5910f3ba0a423df5bcaa75e95850e906aefa7d3e6d8d80d8e84df9e94ebb044ccd9812788e5443f7ee05bc6b587a1aa594c108814f'
}

# Use the database for sessions instead of the cookie-based default,
# which shouldn't be used to store highly confidential information
# (create the session table with "rake db:sessions:create")
# ActionController::Base.session_store = :active_record_store
