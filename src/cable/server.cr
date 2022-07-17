require "mutex"
require "set"

module Cable
  alias Channels = Set(Cable::Channel)

  def self.server
    @@server ||= Server.new
  end

  def self.restart
    if current_server = @@server
      current_server.shutdown
    end
    @@server = Server.new
  end

  class Server
    include Debug

    getter connections = {} of String => Connection
    # Use the pooled connections
    getter redis_publish = Redis::Client.new(URI.parse(Cable.settings.url))
    # Use a single connection
    getter redis_subscribe = Redis::Connection.new(URI.parse(Cable.settings.url))
    getter fiber_channel = ::Channel({String, String}).new

    @channels = {} of String => Channels
    @channel_mutex = Mutex.new

    def initialize
      subscribe_to_internal
      process_subscribed_messages
    end

    def add_connection(connection)
      connections[connection.connection_identifier] = connection
    end

    def remove_connection(connection_id)
      connections.delete(connection_id).try(&.close)
    end

    def subscribe_channel(channel : Channel, identifier : String)
      @channel_mutex.synchronize do
        if !@channels.has_key?(identifier)
          @channels[identifier] = Channels.new
        end

        @channels[identifier] << channel
      end

      redis_subscribe.subscribe(identifier)
    end

    def unsubscribe_channel(channel : Channel, identifier : String)
      @channel_mutex.synchronize do
        if @channels.has_key?(identifier)
          @channels[identifier].delete(channel)

          if @channels[identifier].size == 0
            redis_subscribe.unsubscribe(identifier)

            @channels.delete(identifier)
          end
        else
          redis_subscribe.unsubscribe(identifier)
        end
      end
    end

    # redis only accepts strings, so we should be strict here
    def publish(channel : String, message : String)
      redis_publish.publish(channel, message)
    end

    def send_to_channels(channel_identifier, message)
      return unless @channels.has_key?(channel_identifier)

      parsed_message = safe_decode_message(message)

      @channels[channel_identifier].each do |channel|
        # TODO: would be nice to have a test where we open two connections
        # close one, and make sure the other one receives the message
        if channel.connection.socket.closed?
          channel.close
        else
          Cable::Logger.info { "#{channel.class} transmitting #{parsed_message} (via streamed from #{channel.stream_identifier})" }
          channel.connection.socket.send({
            identifier: channel.identifier,
            message:    parsed_message,
          }.to_json)
        end
      end
    rescue e : IO::Error
      Cable::Logger.error { "IO::Error Exception: #{e.message} -> #{self.class.name}#send_to_channels(channel, message)" }
    end

    def safe_decode_message(message)
      case message
      when String
        JSON.parse(message)
      else
        message
      end
    rescue JSON::ParseException
      message
    end

    def shutdown
      # TODO: This seems to make the specs hang
      # redis_subscribe.run({"unsubscribe"})
      redis_subscribe.unsubscribe("")
      redis_subscribe.close
      redis_publish.close
      connections.each do |_, v|
        v.close
      end
    end

    private def process_subscribed_messages
      server = self
      spawn(name: "Cable::Server - process_subscribed_messages") do
        while received = fiber_channel.receive
          channel, message = received
          server.send_to_channels(channel, message)
          Cable::Logger.debug { "Cable::Server#process_subscribed_messages channel:#{channel} message:#{message}" }
        end
      end
    end

    private def subscribe_to_internal
      spawn(name: "Cable::Server - subscribe") do
        # begin
          redis_subscribe.subscribe("_internal") do |subscription|
            subscription.on_message do |channel, message|
              if channel == "_internal" && message == "ping"
                Cable::Logger.debug { "Cable::Server#subscribe channel:#{channel} message:PONG" }
              elsif channel == "_internal" && message == "debug"
                debug
              else
                fiber_channel.send({channel, message})
                Cable::Logger.debug { "Cable::Server#subscribe channel:#{channel} message:#{message}" }
              end
            end
          end
        # rescue e : IO::Error
        #   # why is redis_subscribe.@socket.closed? here??
        # end
      end
    end
  end
end
