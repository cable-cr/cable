module Cable
  class Channel
    class CloseRedisFiber < Exception; end

    CHANNELS = {} of String => Cable::Channel.class

    macro inherited
      Cable::Channel::CHANNELS[self.name] = self
    end

    getter params
    getter identifier
    getter connection
    getter stream_identifier : String?
    getter reject_subscription : Bool = false

    def initialize(@connection : Cable::Connection, @identifier : String, @params : Hash(String, Cable::Payload::RESULT))
    end

    def reject
      @reject_subscription = true
    end

    def subscription_rejected?
      @reject_subscription
    end

    def subscribed
    end

    def close
      Cable.server.unsubscribe_channel(channel: self, identifier: @stream_identifier.not_nil!) unless @stream_identifier.nil?
      Cable::Logger.info "#{self.class.name} stopped streaming from #{identifier}"
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
      Cable.server.subscribe_channel(channel: self, identifier: stream_identifier)
      Cable::Logger.info "#{self.class} is streaming from #{stream_identifier}"
    end

    def self.broadcast_to(channel : String, message : JSON::Any)
      Cable::Logger.info "[ActionCable] Broadcasting to #{channel}: #{message}"
      Cable.server.publish(channel, message.to_json)
    end

    # It's important that we don't call message.to_json
    def self.broadcast_to(channel : String, message : String)
      Cable::Logger.info "[ActionCable] Broadcasting to #{channel}: #{message}"
      Cable.server.publish(channel, message)
    end

    def self.broadcast_to(channel : String, message : Hash(String, String))
      Cable::Logger.info "[ActionCable] Broadcasting to #{channel}: #{message}"
      Cable.server.publish(channel, message.to_json)
    end
  end
end
