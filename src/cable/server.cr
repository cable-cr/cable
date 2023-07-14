require "mutex"
require "set"

module Cable
  alias Channels = Set(Cable::Channel)

  def self.server
    @@server ||= Server.new
  end

  def self.reset_server
    @@server = nil
  end

  def self.restart
    if current_server = @@server
      current_server.shutdown
      Cable::Logger.error { "Cable.restart" }
    end
    @@server = Server.new
  end

  class Server
    include Debug

    getter errors = 0
    getter connections = {} of String => Cable::Connection
    getter fiber_channel = ::Channel({String, String}).new
    getter pinger : Cable::RedisPinger do
      Cable::RedisPinger.new(self)
    end
    getter backend : Cable::BackendCore do
      Cable.settings.backend_class.new
    end
    getter backend_publish do
      backend.publish_connection
    end
    getter backend_subscribe do
      backend.subscribe_connection
    end

    @channels = {} of String => Channels
    @channel_mutex = Mutex.new

    def initialize
      # load the connections
      backend
      subscribe
      process_subscribed_messages
    rescue e
      Cable.settings.on_error.call(e, "Cable::Server.initialize")
      raise e
    end

    def remote_connections
      RemoteConnections.new(self)
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

      backend.subscribe(identifier)
    end

    def unsubscribe_channel(channel : Channel, identifier : String)
      @channel_mutex.synchronize do
        if @channels.has_key?(identifier)
          @channels[identifier].delete(channel)

          if @channels[identifier].size == 0
            backend.unsubscribe(identifier)

            @channels.delete(identifier)
          end
        else
          backend.unsubscribe(identifier)
        end
      end
    end

    # redis only accepts strings, so we should be strict here
    def publish(channel : String, message : String)
      backend.publish_message(channel, message)
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
      Cable.settings.on_error.call(e, "IO::Error Exception: #{e.message} -> #{self.class.name}#send_to_channels(channel, message)")
    end

    def send_to_internal_channels(channel_identifier : String, message : String)
      if internal_channel = connections[channel_identifier]?
        case message
        when Cable.message(:disconnect)
          Cable::Logger.info { "Removing connection (#{channel_identifier})" }
          internal_channel.close
        end
      end
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
      begin
        backend.close_subscribe_connection
        backend.close_publish_connection
      rescue e : IO::Error
        # the @writer IO is closed already
        Cable::Logger.debug { "Cable::Server#shutdown Connection to redis was severed: #{e.message}" }
      end
      pinger.stop
      connections.each do |_k, v|
        v.close
      end
    end

    def restart?
      errors > Cable.settings.restart_error_allowance
    end

    def count_error!
      @channel_mutex.synchronize do
        @errors += 1
      end
    end

    private def process_subscribed_messages
      server = self
      spawn(name: "Cable::Server - process_subscribed_messages") do
        while received = fiber_channel.receive
          channel, message = received
          if channel.includes?("cable_internal")
            server.send_to_internal_channels(channel, message)
          else
            server.send_to_channels(channel, message)
          end
          Cable::Logger.debug { "Cable::Server#process_subscribed_messages channel:#{channel} message:#{message}" }
        end
      end
    end

    private def subscribe
      spawn(name: "Cable::Server - subscribe") do
        backend.open_subscribe_connection("_internal")
      end
    end
  end
end
