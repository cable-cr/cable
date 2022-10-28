module Cable
  abstract class BackendCore
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
end
