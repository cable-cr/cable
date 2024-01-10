require "habitat"
require "json"
require "./cable/**"

# TODO: Write documentation for `Cable`
module Cable
  VERSION = "0.3.1"

  INTERNAL = {
    message_types: {
      welcome:      "welcome",
      disconnect:   "disconnect",
      ping:         "ping",
      confirmation: "confirm_subscription",
      rejection:    "reject_subscription",
      unsubscribe:  "confirm_unsubscription",
    },
    channel:            "_internal",
    disconnect_reasons: {
      unauthorized:    "unauthorized",
      invalid_request: "invalid_request",
      server_restart:  "server_restart",
      remote:          "remote",
    },
    default_mount_path: "/cable",
    protocols:          ["actioncable-v1-json", "actioncable-unsupported"],
  }

  Habitat.create do
    setting route : String = Cable.message(:default_mount_path), example: "/cable"
    setting token : String = "token", example: "token"
    setting url : String = ENV.fetch("REDIS_URL", "redis://localhost:6379"), example: "redis://localhost:6379"
    setting disable_sec_websocket_protocol_header : Bool = false
    setting backend_class : Cable::BackendCore.class = Cable::RegistryBackend, example: "Cable::RedisBackend"
    setting backend_ping_interval : Time::Span = 15.seconds
    @[Deprecated("Use backend_ping_interval")]
    setting redis_ping_interval : Time::Span do
      backend_ping_interval
    end
    setting restart_error_allowance : Int32 = 20
    setting on_error : Proc(Exception, String, Nil) = ->(exception : Exception, message : String) do
      Cable::Logger.error(exception: exception) { message }
    end

    # DEPRECATED
    # only use if you are using stefanwille/crystal-redis
    # AND you want to use the connection pool
    setting pool_redis_publish : Bool = false
    setting redis_pool_size : Int32 = 5
    setting redis_pool_timeout : Float64 = 5.0
  end

  def self.message(event : Symbol)
    INTERNAL[:message_types][event]
  end
end
