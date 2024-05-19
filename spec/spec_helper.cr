require "spec"
require "../src/cable"
require "../src/backend/redis/backend"
require "../src/backend/dev/backend"
require "./support/fake_exception_service"
require "./support/request_helpers"
require "./support/dummy_socket"
require "./support/application_cable/connection"
require "./support/application_cable/channel"
require "./support/channels/*"

Cable.configure do |settings|
  settings.route = "/updates"
  settings.token = "test_token"
  settings.url = ENV.fetch("CABLE_BACKEND_URL", "redis://localhost:6379")
  settings.backend_class = Cable::RedisBackend
  settings.backend_ping_interval = 2.seconds
  settings.restart_error_allowance = 2
  settings.on_error = ->(exception : Exception, message : String) do
    FakeExceptionService.notify(exception, message: message)
  end
end

Spec.before_each do
  Cable.restart
  FakeExceptionService.clear
  Cable::DevBackend.reset
end
