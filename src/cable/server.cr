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

    # The String key is the `connection_identifier` value for `Cable::Connection`
    getter connections = {} of String => Cable::Connection
    getter errors = 0
    getter fiber_channel = ::Channel({String, String}).new
    getter pinger : Cable::BackendPinger do
      Cable::BackendPinger.new(self)
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

    @channels : Hash(String, Channels)
    @channel_mutex : Mutex

    def initialize
      @channels = {} of String => Channels
      @channel_mutex = Mutex.new

      begin
        # load the connections
        backend
        subscribe
        process_subscribed_messages
      rescue e
        Cable.settings.on_error.call(e, "Cable::Server.initialize")
        raise e
      end
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

    # You shouldn't rely on these following two methods
    # for an exhaustive array of connections and channels
    # if your application can spawn more than one Cable.server instance.

    # Only returns connections opened on this instance.
    def active_connections_for(token : String) : Array(Connection)
      connections.values.select { |connection| connection.token == token && !connection.closed? }
    end

    # Only returns channel subscriptions opened on this instance.
    def subscribed_channels_for(token : String) : Array(Channel)
      active_connections_for(token).sum(&.channels)
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

    # Some backends only accept strings, so we should be strict here
    def publish(channel : String, message : String)
      backend.publish_message(channel, message)
    end

    def send_to_channels(channel_identifier, message)
      return unless @channels.has_key?(channel_identifier)

      parsed_message = safe_decode_message(message)

      begin
        @channels[channel_identifier].each do |channel|
          # TODO: would be nice to have a test where we open two connections
          # close one, and make sure the other one receives the message
          if channel.connection.closed?
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
        Cable.settings.on_error.call(e, "IO::Error Exception: #{e.message}: #{parsed_message} -> Cable::Server#send_to_channels(channel, message)")
      end
    end

    def send_to_internal_connections(connection_identifier : String, message : String)
      if internal_connection = connections[connection_identifier]?
        case message
        when Cable.message(:disconnect)
          Cable::Logger.info { "Removing connection (#{connection_identifier})" }
          internal_connection.close
          remove_connection(connection_identifier)
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
        Cable::Logger.debug { "Cable::Server#shutdown Connection to backend was severed: #{e.message}" }
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
          if channel.starts_with?("cable_internal")
            identifier = channel.split('/').last
            connection_identifier = server.connections.keys.find!(&.starts_with?(identifier))
            server.send_to_internal_connections(connection_identifier, message)
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
