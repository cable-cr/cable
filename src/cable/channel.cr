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
    getter redis
    getter stream_identifier : String?

    def initialize(@connection : Cable::Connection, @identifier : String, @params : Hash(String, String))
      @redis = Redis.new
    end

    def subscribed
      # raise Exception.new("Implement the `subscribed` method")
    end

    def close
      redis.unsubscribe("cable:#{identifier}")
      Logger.info "#{self.class.to_s} stopped streaming from #{identifier}"
      unsubscribed
    end

    def unsubscribed
    end

    def receive(message)
    end

    def perform(action, message)
    end

    def stream_from(identifier)
      @stream_identifier = identifier
      spawn do
        begin
          redis.subscribe("cable:#{identifier}") do |on|
            on.message do |channel, message|
              connection.broadcast_to(self, message)
            end

            on.unsubscribe do |channel, subscriptions|
              raise CloseRedisFiber.new("Unsubscribed")
            end
          end
        rescue e : CloseRedisFiber
        end
      end
      Logger.info "#{self.class.to_s} is streaming from #{identifier}"
    end

    def self.broadcast_to(channel : String, message : JSON::Any)
      Logger.info "[ActionCable] Broadcasting to #{channel.class}: #{message}"
      Redis::PooledClient.new.publish("cable:#{channel}", message.to_json)
    end

    def self.broadcast_to(channel : String, message : Hash(String, String))
      Logger.info "[ActionCable] Broadcasting to #{channel.class}: #{message}"
      Redis::PooledClient.new.publish("cable:#{channel}", message.to_json)
    end
  end
end
