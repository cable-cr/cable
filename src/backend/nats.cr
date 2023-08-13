require "nats"

module Cable
  class NATSBackend < BackendCore
    register "nats"

    getter nats : NATS::Client do
      NATS::Client.new(URI.parse(Cable.settings.url))
    end
    getter streams = Hash(String, Set(NATS::Subscription)).new { |streams, channel|
      streams[channel] = Set(NATS::Subscription).new
    }

    def subscribe_connection
      nats
    end

    def publish_connection
      nats
    end

    def close_subscribe_connection
      nats.close rescue nil
    end

    def close_publish_connection
      nats.close rescue nil
    end

    def open_subscribe_connection(channel)
      nats
    end

    def publish_message(stream_identifier : String, message : String)
      nats.publish stream_identifier, message
    end

    def subscribe(stream_identifier : String)
      subscription = nats.subscribe stream_identifier, queue_group: object_id.to_s do |msg|
        Cable.server.fiber_channel.send({
          stream_identifier,
          String.new(msg.body),
        })
      end
      streams[stream_identifier] << subscription
    end

    def unsubscribe(stream_identifier : String)
      if subscriptions = streams.delete(stream_identifier)
        subscriptions.each do |subscription|
          nats.unsubscribe subscription
        end
      end
    end

    def ping_redis_subscribe
      nats.ping
    end

    def ping_redis_publish
      nats.ping
    end
  end
end
