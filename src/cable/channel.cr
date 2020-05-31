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

    def initialize(@connection : Cable::Connection, @identifier : String, @params : Hash(String, Cable::Payload::RESULT))
      if ENV["REDIS_URL"]? 
        @redis = Redis.new(url: ENV["REDIS_URL"])
      else
        @redis = Redis.new
      end
    end

    def subscribed
      # raise Exception.new("Implement the `subscribed` method")
    end

    def close
      redis.unsubscribe("cable:#{identifier}")
      Cable::Logger.info "#{self.class.name} stopped streaming from #{identifier}"
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
      Cable::Logger.info "#{self.class.to_s} is streaming from #{identifier}"
    end

    def self.broadcast_to(channel : String, message : JSON::Any)
      Cable::Logger.info "[ActionCable] Broadcasting to #{channel}: #{message}"
      Redis::PooledClient.new.publish("cable:#{channel}", message.to_json)
    end

    def self.broadcast_to(channel : String, message : Hash(String, String))
      Cable::Logger.info "[ActionCable] Broadcasting to #{channel}: #{message}"
      Redis::PooledClient.new.publish("cable:#{channel}", message.to_json)
    end
  end
end
