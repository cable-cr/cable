require "habitat"
require "json"
require "redis"
require "./cable/**"

# TODO: Write documentation for `Cable`
module Cable
  VERSION = "0.1.1"

  INTERNAL = {
    message_types: {
      welcome:      "welcome",
      disconnect:   "disconnect",
      ping:         "ping",
      confirmation: "confirm_subscription",
      rejection:    "reject_subscription",
    },
    disconnect_reasons: {
      unauthorized:    "unauthorized",
      invalid_request: "invalid_request",
      server_restart:  "server_restart",
    },
    default_mount_path: "/cable",
    protocols:          ["actioncable-v1-json", "actioncable-unsupported"].freeze,
  }

  Habitat.create do
    setting route : String = "/cable", example: "/cable"
    setting token : String = "token", example: "token"
    setting url : String = ENV.fetch("REDIS_URL", "redis://localhost:6379"), example: "redis://localhost:6379"
  end
  # TODO: Put your code here
end
