require "redis"

module Cable
  class Connection
    @@mock : ApplicationCable::Connection?

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
      @redis = Redis.new
      connect
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
    end

    def reject_unauthorized_connection
      # TODO: Reject Connection
    end

    def receive(message)
      payload = Cable::Payload.from_json(message)

      return subscribe(payload.identifier) if payload.command == "subscribe"
      return message(payload.identifier, payload.data || "") if payload.command == "message"
    end

    def subscribe(payload_identifier)
      identifier = Cable::Identifier.from_json(payload_identifier)
      channel = Cable::Channel::CHANNELS[identifier.channel].new(connection: self, identifier: payload_identifier, params: identifier.params || {} of String => String)
      channel.subscribed
      Connection::CHANNELS[internal_identifier] ||= {} of String => Cable::Channel
      Connection::CHANNELS[internal_identifier][payload_identifier] = channel
      Logger.info "#{identifier.channel} is transmitting the subscription confirmation"
      socket.send({type: "confirm_subscription", identifier: payload_identifier}.to_json)
    end

    def message(payload_identifier, payload_data : String)
      identifier = Cable::Identifier.from_json(payload_identifier)
      parsed_message = JSON.parse(payload_data).as_h?

      parsed_message = JSON.parse(payload_data).as_s unless parsed_message

      if Connection::CHANNELS[internal_identifier].has_key?(payload_identifier)
        channel = Connection::CHANNELS[internal_identifier][payload_identifier]
        if parsed_message.is_a?(Hash) && parsed_message.has_key?("action")
          action = parsed_message.delete("action")
          Logger.info "#{channel.class}#perform(#{action}, #{parsed_message})"
          channel.perform(action, parsed_message)
        else
          Logger.info "#{channel.class}#receive(#{payload_data})"
          channel.receive(parsed_message)
        end
      end
    end

    def broadcast_to(channel : Cable::Channel, message : String)
      parsed_message = JSON.parse(message)
      if stream_identifier = channel.stream_identifier
        Logger.info "#{channel.class} transmitting #{message} (via streamed from #{channel.stream_identifier})"
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
