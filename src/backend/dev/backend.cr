module Cable
  class DevBackend < Cable::BackendCore
    # Store the published `stream_identifier` and `message`
    class_getter published_messages = [] of Tuple(String, String)

    # Store the `stream_identifier` on `subscribe`
    class_getter subscriptions = [] of String

    def self.reset
      @@published_messages.clear
      @@subscriptions.clear
    end

    def publish_message(stream_identifier : String, message : String)
      @@published_messages << {stream_identifier, message}
    end

    def subscribe_connection
    end

    def publish_connection
    end

    def close_subscribe_connection
    end

    def close_publish_connection
    end

    def open_subscribe_connection(channel)
    end

    def subscribe(stream_identifier : String)
      @@subscriptions << stream_identifier
    end

    def unsubscribe(stream_identifier : String)
      @@subscriptions.delete(stream_identifier)
    end

    def ping_subscribe_connection
    end

    def ping_publish_connection
    end
  end
end
