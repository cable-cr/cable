module Cable
  class Channel
    CHANNELS = {} of String => Cable::Channel.class

    macro inherited
      Cable::Channel::CHANNELS[self.name] = self
    end

    # @override in after_subscribed macro
    def run_after_subscribed_callbacks
    end

    # Run `block` after the subscription is created.
    macro after_subscribed(*callbacks)
      def run_after_subscribed_callbacks
        {% for callback in callbacks %}
          {{callback.id}}
        {% end %}
      end
    end

    getter params : Hash(String, Cable::Payload::RESULT)
    getter identifier : String
    getter connection : Cable::Connection
    getter stream_identifier : String?
    getter? subscription_rejected : Bool = false

    def initialize(@connection : Cable::Connection, @identifier : String, @params : Hash(String, Cable::Payload::RESULT))
    end

    def reject
      @subscription_rejected = true
    end

    def subscribed
    end

    def close
      if stream_id = stream_identifier.presence
        Cable.server.unsubscribe_channel(channel: self, identifier: stream_id)
        Cable::Logger.info { "#{self.class.name} stopped streaming from #{identifier}" }
      end

      unsubscribed
    end

    def unsubscribed
    end

    def receive(message)
    end

    def perform(action, message)
    end

    def stream_from(stream_identifier : String | Symbol)
      @stream_identifier = stream_identifier.to_s
    end

    def self.broadcast_to(channel : String, message : JSON::Any | Hash(String, String))
      Cable::Logger.info { "[ActionCable] Broadcasting to #{channel}: #{message}" }
      Cable.server.publish(channel, message.to_json)
    end

    # It's important that we don't call message.to_json
    def self.broadcast_to(channel : String, message : String)
      Cable::Logger.info { "[ActionCable] Broadcasting to #{channel}: #{message}" }
      Cable.server.publish(channel, message)
    end

    def broadcast(message : String | JSON::Any | Hash(String, String))
      if stream_id = stream_identifier.presence
        Cable::Logger.info { "[ActionCable] Broadcasting to #{self.class}: #{message}" }
        Cable.server.send_to_channels(stream_id, message)
      else
        Cable::Logger.error { "#{self.class}.transmit(message : #{message.class}) with #{message} without already using stream_from(stream_identifier)" }
      end
    end

    # broadcast single message to single connection for this channel
    def transmit(message : String | JSON::Any | Hash(String, String))
      Cable::Logger.info { "[ActionCable] transmitting to #{self.class}: #{message}" }
      connection.send_message({
        identifier: identifier,
        message:    Cable.server.safe_decode_message(message),
      }.to_json)
    end
  end
end
