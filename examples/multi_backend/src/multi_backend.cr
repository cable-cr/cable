require "turbo/cable"
require "cable/backend/nats"
require "cable/backend/redis/backend"

module AppCable
  class Connection < Cable::Connection
    identified_by id

    getter id = UUID.random.to_s

    def connect
    end
  end
end

Cable.configure do |settings|
  settings.route = "/cable" # the URL your JS Client will connect
  # settings.url = "redis:///"
  # settings.url = ENV.fetch("NATS_URL", "nats:///")
  settings.url = ENV.fetch("CABLE_BACKEND_URL", "redis:///")
end

Turbo::StreamsChannel.signing_key = "this is my signing key"

spawn do
  loop do
    duration = Time.measure do
      Turbo::StreamsChannel.broadcast_update_to "time",
        message: Time.local.to_s
    end
    sleep 1.second - duration
  end
end

http = HTTP::Server.new([
  HTTP::LogHandler.new,
  Cable::Handler(AppCable::Connection).new,
]) do |context|
  context.response << <<-HTML
    <!doctype html>
    #{Turbo.javascript_tag}
    #{Turbo.cable_tag}
    #{Turbo::Frame.new(id: "time") { }}
    #{Turbo.stream_from "time"}
    HTML
end

http.listen 3200
