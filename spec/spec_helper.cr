require "spec"
require "../src/cable"
require "./support/application_cable/connection"
require "./support/application_cable/channel"
require "./support/channels/*"

Cable.configure do |settings|
  settings.route = "/updates"
  settings.token = "test_token"
end

Spec.before_each do
  Cable.restart
end
