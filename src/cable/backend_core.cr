module Cable
  abstract class BackendCore
    def self.register(uri_scheme : String, backend : BackendCore.class = self)
      ::Cable::RegistryBackend.register uri_scheme, backend
    end

    # connection management
    abstract def subscribe_connection
    abstract def publish_connection
    abstract def close_subscribe_connection
    abstract def close_publish_connection

    # internal pub/sub
    abstract def open_subscribe_connection(channel)

    # external pub/sub
    abstract def publish_message(stream_identifier : String, message : String)

    # channel management
    abstract def subscribe(stream_identifier : String)
    abstract def unsubscribe(stream_identifier : String)

    # ping/pong

    abstract def ping_redis_subscribe
    abstract def ping_redis_publish
  end

  class RegistryBackend < BackendCore
    REGISTERED_BACKENDS = {} of String => BackendCore.class

    def self.register(uri_scheme : String, backend : BackendCore.class = self)
      REGISTERED_BACKENDS[uri_scheme] = backend
    end

    @backend : BackendCore

    def initialize
      @backend = REGISTERED_BACKENDS[URI.parse(::Cable.settings.url).scheme].new
    end

    delegate(
      subscribe_connection,
      publish_connection,
      close_subscribe_connection,
      close_publish_connection,
      open_subscribe_connection,
      publish_message,
      subscribe,
      unsubscribe,
      ping_redis_subscribe,
      ping_redis_publish,
      to: @backend
    )
  end
end
