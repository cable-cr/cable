require "spec"
require "../src/cable"
require "../src/backend/redis/backend"
require "./support/fake_exception_service"
require "./support/application_cable/connection"
require "./support/application_cable/channel"
require "./support/channels/*"

Cable.configure do |settings|
  settings.route = "/updates"
  settings.token = "test_token"
  settings.redis_ping_interval = 2.seconds
  settings.restart_error_allowance = 2
  settings.on_error = ->(exception : Exception, message : String) do
    FakeExceptionService.notify(exception, message: message)
  end
end

Spec.before_each do
  Cable.restart
  FakeExceptionService.clear
end
