require "habitat"
require "json"
require "redis"
require "./cable/**"

# TODO: Write documentation for `Cable`
module Cable
  VERSION = "0.2.2"

  INTERNAL = {
    message_types: {
      welcome:      "welcome",
      disconnect:   "disconnect",
      ping:         "ping",
      confirmation: "confirm_subscription",
      rejection:    "reject_subscription",
      unsubscribe:  "confirm_unsubscription",
    },
    disconnect_reasons: {
      unauthorized:    "unauthorized",
      invalid_request: "invalid_request",
      server_restart:  "server_restart",
    },
    default_mount_path: "/cable",
    protocols:          ["actioncable-v1-json", "actioncable-unsupported"],
  }

  Habitat.create do
    setting route : String = Cable.message(:default_mount_path), example: "/cable"
    setting token : String = "token", example: "token"
    setting url : String = ENV.fetch("REDIS_URL", "redis://localhost:6379"), example: "redis://localhost:6379"
    setting disable_sec_websocket_protocol_header : Bool = false
    setting redis_ping_interval : Time::Span = 15.seconds
  end

  def self.message(event : Symbol)
    INTERNAL[:message_types][event]
  end
end
