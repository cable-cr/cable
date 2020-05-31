require "redis"

module Cable
  class Connection
    class UnathorizedConnectionException < Exception; end

    @@mock : Cable::Connection?

    property internal_identifier : String = "0"
    getter token : String

    CHANNELS = {} of String => Hash(String, Cable::Channel)

    getter socket
    getter redis

    def identifier
      ""
    end

    macro identified_by(name)
      @{{name.id}} : String = ""
      
      def {{name.id}}=(value : String)
        @{{name.id}} = value
      end
    
      def {{name.id}}
        @{{name.id}}
      end

      private def internal_identifier
        @{{name.id}}
      end
    end

    macro owned_by(type_definition)
      @{{type_definition.var}} : {{type_definition.type}}?
      
      def {{type_definition.var}}=(value : {{type_definition.type}})
        @{{type_definition.var}} = value
      end

      def {{type_definition.var}}
        @{{type_definition.var}}
      end
    end

    def self.use_mock(mock, &block)
      @@mock = mock

      yield

      @@mock = nil
    end

    def self.build(request : HTTP::Request, socket : HTTP::WebSocket)
      if mock = @@mock
        return mock
      else
        self.new(request, socket)
      end
    end

    def initialize(@request : HTTP::Request, @socket : HTTP::WebSocket)
      @token = @request.query_params.fetch(Cable.settings.token) {
        raise "Not token on params"
      }
      if ENV["REDIS_URL"]? 
        @redis = Redis.new(url: ENV["REDIS_URL"])
      else
        @redis = Redis.new
      end

      begin
        connect
      rescue e : UnathorizedConnectionException
        socket.close
        Cable::Logger.info("An unauthorized connection attempt was rejected")
      end
    end

    def connect
      raise Exception.new("Implement the `connect` method")
    end

    def close
      return true unless Connection::CHANNELS.has_key?(internal_identifier)
      Connection::CHANNELS[internal_identifier].each do |identifier, channel|
        channel.close
        Connection::CHANNELS[internal_identifier].delete(identifier)
      end
      socket.close
    end

    def reject_unauthorized_connection
      raise UnathorizedConnectionException.new
    end

    def receive(message)
      payload = Cable::Payload.new(message)

      return subscribe(payload) if payload.command == "subscribe"
      return message(payload) if payload.command == "message"
    end

    def subscribe(payload)
      channel = Cable::Channel::CHANNELS[payload.channel].new(connection: self, identifier: payload.identifier, params: payload.channel_params)
      channel.subscribed
      Connection::CHANNELS[internal_identifier] ||= {} of String => Cable::Channel
      Connection::CHANNELS[internal_identifier][payload.identifier] = channel
      Cable::Logger.info "#{payload.channel} is transmitting the subscription confirmation"
      socket.send({type: "confirm_subscription", identifier: payload.identifier}.to_json)
    end

    def message(payload)
      if Connection::CHANNELS[internal_identifier].has_key?(payload.identifier)
        channel = Connection::CHANNELS[internal_identifier][payload.identifier]
        if payload.action?
          Cable::Logger.info "#{channel.class}#perform(\"#{payload.action}\", #{payload.data})"
          channel.perform(payload.action, payload.data)
        else
          begin
            Cable::Logger.info "#{channel.class}#receive(#{payload.data})"
            channel.receive(payload.data)
          rescue e : TypeCastError
          end
        end
      end
    end

    def broadcast_to(channel : Cable::Channel, message : String)
      parsed_message = JSON.parse(message)
      if stream_identifier = channel.stream_identifier
        Cable::Logger.info "#{channel.class} transmitting #{parsed_message} (via streamed from #{channel.stream_identifier})"
      end
      socket.send({
        identifier: channel.identifier,
        message:    parsed_message,
      }.to_json)
    end

    def self.broadcast_to(channel : String, message : String)
      Redis::PooledClient.new.publish("cable:#{channel}", message)
    end
  end
end
