ActionController::Routing::Routes.draw do |map|
  map.home '/', :controller => 'main', :action => 'index'
  map.connect ':controller/:action/:id'
  map.connect ':controller/:action/:id.:format'
end
