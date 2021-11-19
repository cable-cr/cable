module Cable
  class Channel
    class CloseRedisFiber < Exception; end

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

    getter params
    getter identifier
    getter connection
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
      Cable.server.unsubscribe_channel(channel: self, identifier: @stream_identifier.not_nil!) unless @stream_identifier.nil?
      Cable::Logger.info { "#{self.class.name} stopped streaming from #{identifier}" }
      unsubscribed
    end

    def unsubscribed
    end

    def receive(message)
    end

    def perform(action, message)
    end

    def stream_from(stream_identifier)
      @stream_identifier = stream_identifier
    end

    def self.broadcast_to(channel : String, message : JSON::Any)
      Cable::Logger.info { "[ActionCable] Broadcasting to #{channel}: #{message}" }
      Cable.server.publish(channel, message.to_json)
    end

    # It's important that we don't call message.to_json
    def self.broadcast_to(channel : String, message : String)
      Cable::Logger.info { "[ActionCable] Broadcasting to #{channel}: #{message}" }
      Cable.server.publish(channel, message)
    end

    def self.broadcast_to(channel : String, message : Hash(String, String))
      Cable::Logger.info { "[ActionCable] Broadcasting to #{channel}: #{message}" }
      Cable.server.publish(channel, message.to_json)
    end

    def broadcast(message : String)
      if stream_identifier.nil?
        Cable::Logger.error { "#{self.class}.transmit(message : String) with #{message} without already using stream_from(stream_identifier)" }
      else
        Cable::Logger.info { "[ActionCable] Broadcasting to #{self.class}: #{message}" }
        Cable.server.send_to_channels(stream_identifier.not_nil!, message)
      end
    end

    def broadcast(message : JSON::Any)
      if stream_identifier.nil?
        Cable::Logger.error { "#{self.class}.transmit(message : JSON::Any) with #{message} without already using stream_from(stream_identifier)" }
      else
        Cable::Logger.info { "[ActionCable] Broadcasting to #{self.class}: #{message}" }
        Cable.server.send_to_channels(stream_identifier.not_nil!, message)
      end
    end

    def broadcast(message : Hash(String, String))
      if stream_identifier.nil?
        Cable::Logger.error { "#{self.class}.transmit(message : Hash(String, String)) with #{message} without already using stream_from(stream_identifier)" }
      else
        Cable::Logger.info { "[ActionCable] Broadcasting to #{self.class}: #{message}" }
        Cable.server.send_to_channels(stream_identifier.not_nil!, message.to_json)
      end
    end

    # broadcast single message to single connection for this channel
    def transmit(message : String)
      Cable::Logger.info { "[ActionCable] transmitting to #{self.class}: #{message}" }
      connection.socket.send({
        identifier: identifier,
        message:    Cable.server.safe_decode_message(message),
      }.to_json)
    end

    # broadcast single message to single connection for this channel
    def transmit(message : JSON::Any)
      Cable::Logger.info { "[ActionCable] transmitting to #{self.class}: #{message}" }
      connection.socket.send({
        identifier: identifier,
        message:    Cable.server.safe_decode_message(message),
      }.to_json)
    end

    # broadcast single message to single connection for this channel
    def transmit(message : Hash(String, String))
      Cable::Logger.info { "[ActionCable] transmitting to #{self.class}: #{message}" }
      connection.socket.send({
        identifier: identifier,
        message:    Cable.server.safe_decode_message(message),
      }.to_json)
    end
  end
end
