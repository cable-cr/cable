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
    getter connections = {} of String => Connection
    getter redis_subscribe = Redis.new(url: Cable.settings.url)
    getter redis_publish = Redis.new(url: Cable.settings.url)
    getter fiber_channel = ::Channel({String, String}).new

    def initialize
      @channels = {} of String => Channels
      @channel_mutex = Mutex.new
      subscribe
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

      request = Redis::Request.new
      request << "subscribe"
      request << identifier
      redis_subscribe._connection.send(request)
    end

    def unsubscribe_channel(channel : Channel, identifier : String)
      @channel_mutex.synchronize do
        if @channels.has_key?(identifier)
          @channels[identifier].delete(channel)

          if @channels[identifier].size == 0
            request = Redis::Request.new
            request << "unsubscribe"
            request << identifier
            redis_subscribe._connection.send(request)

            @channels.delete(identifier)
          end
        else
          request = Redis::Request.new
          request << "unsubscribe"
          request << identifier
          redis_subscribe._connection.send(request)
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

    def debug_json
      _channels = {} of String => Set(String)

      @channels.each do |k, v|
        channels[v.first.class.to_s] ||= Set{k}
        channels[v.first.class.to_s] << k
      end

      {
        "connections"         => @connections.size,
        "channels"            => @channels.size,
        "channels_mounted"    => _channels,
        "connections_mounted" => @connections.map do |key, connection|
          connections_mounted_channels = [] of Hash(String, String | Nil)
          @channels.each do |_, v|
            v.each do |channel|
              next unless channel.connection.connection_identifier == key
              connections_mounted_channels << {
                "channel" => channel.class.to_s,
                "key"     => channel.stream_identifier,
              }
            end
          end

          {
            "key"        => key,
            "identifier" => connection.identifier,
            "started_at" => connection.started_at.to_s("%Y-%m-%dT%H:%M:%S.%6N"),
            "channels"   => connections_mounted_channels,
          }
        end,
      }
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

    def debug
      Cable::Logger.debug { "-" * 80 }
      Cable::Logger.debug { "Some Good Information" }
      Cable::Logger.debug { "Connections" }
      @connections.each do |k, v|
        Cable::Logger.debug { "Connection Key: #{k}" }
      end
      Cable::Logger.debug { "Channels" }
      @channels.each do |k, v|
        Cable::Logger.debug { "Channel Key: #{k}" }
        Cable::Logger.debug { "Channels" }
        v.each do |channel|
          Cable::Logger.debug { "From Channel: #{channel.connection.connection_identifier}" }
          Cable::Logger.debug { "Params: #{channel.params}" }
          Cable::Logger.debug { "ID: #{channel.identifier}" }
          Cable::Logger.debug { "Stream ID:: #{channel.stream_identifier}" }
        end
      end
      Cable::Logger.debug { "-" * 80 }
    end

    def shutdown
      request = Redis::Request.new
      request << "unsubscribe"
      redis_subscribe._connection.send(request)
      redis_subscribe.close
      redis_publish.close
      connections.each do |k, v|
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

    private def subscribe
      spawn(name: "Cable::Server - subscribe") do
        redis_subscribe.subscribe("_internal") do |on|
          on.message do |channel, message|
            if channel == "_internal" && message == "debug"
              puts self.debug
            else
              fiber_channel.send({channel, message})
              Cable::Logger.debug { "Cable::Server#subscribe channel:#{channel} message:#{message}" }
            end
          end
        end
      end
    end
  end
end
