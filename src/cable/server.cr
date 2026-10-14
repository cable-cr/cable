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
    @connections : Hash(String, Cable::Connection)
    @connections_mutex : Mutex

    def initialize
      @channels = {} of String => Channels
      @channel_mutex = Mutex.new
      @connections = {} of String => Cable::Connection
      @connections_mutex = Mutex.new

      begin
        # load the connections
        backend
        subscribe
        process_subscribed_messages
      rescue e
        Cable.settings.on_error.call(e, "Cable::Server.initialize", nil)
        raise e
      end
    end

    def remote_connections
      RemoteConnections.new(self)
    end

    # Returns the current connections
    def connections : Hash(String, Cable::Connection)
      @connections_mutex.synchronize do
        @connections.dup
      end
    end

    def add_connection(connection)
      @connections_mutex.synchronize do
        @connections[connection.connection_identifier] = connection
      end
    end

    def remove_connection(connection_id)
      connection = @connections_mutex.synchronize do
        @connections.delete(connection_id)
      end
      connection.try(&.close)
    end

    # You shouldn't rely on these following two methods
    # for an exhaustive array of connections and channels
    # if your application can spawn more than one Cable.server instance.

    # Only returns connections opened on this instance.
    def active_connections_for(token : String) : Array(Connection)
      @connections_mutex.synchronize do
        @connections.values.select { |connection| connection.token == token && !connection.closed? }
      end
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
      stale = [] of Cable::Channel
      transmitted = 0

      @channels[channel_identifier].each do |channel|
        if channel.connection.closed?
          stale << channel
        else
          channel.connection.socket.send({
            identifier: channel.identifier,
            message:    parsed_message,
          }.to_json)
          transmitted += 1
        end
      rescue e : Exception
        stale << channel if e.is_a?(IO::Error)
        Cable.settings.on_error.call(e, "#{e.class} Exception: #{e.message}: #{parsed_message} -> Cable::Server#send_to_channels(channel, message)", channel.connection)
      end

      # Log once per broadcast event rather than once per subscriber, so a
      # message fanned out to N connections produces a single log line.
      if transmitted > 0
        Cable::Logger.info { "Transmitting #{parsed_message} to #{transmitted} subscriber#{"s" if transmitted > 1} (via streamed from #{channel_identifier})" }
      end

      evict_stale_channels(stale, channel_identifier) unless stale.empty?
    end

    def send_to_internal_connections(connection_identifier : String, message : String)
      internal_connection = @connections_mutex.synchronize do
        @connections[connection_identifier]?
      end
      if internal_connection
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
      connections_to_close = @connections_mutex.synchronize do
        @connections.values.dup
      end
      connections_to_close.each do |connection|
        connection.close
      rescue e : Exception
        Cable.settings.on_error.call(e, "Exception: #{e.message} -> Cable::Server#shutdown(connection.close)", connection)
      end
      # Close the channel so the `process_subscribed_messages` fiber stops
      # blocking on `receive` and exits cleanly instead of leaking across restarts.
      begin
        fiber_channel.close
      rescue e : Exception
        Cable.settings.on_error.call(e, "Exception: #{e.message} -> Cable::Server#shutdown(fiber_channel.close)", nil)
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

    # These are channels that were already closed or raised some exception. Clear them out
    private def evict_stale_channels(stale : Array(Cable::Channel), channel_identifier : String)
      stale.each do |channel|
        unsubscribe_channel(channel: channel, identifier: channel_identifier)
        Cable::Logger.info { "#{channel.class.name} stopped streaming from #{channel.identifier}" }
      rescue e : Exception
        Cable.settings.on_error.call(e, "Exception: #{e.message} -> Cable::Server#send_to_channels(stale channel unsubscribe)", channel.connection)
      end

      # Run this asynchronously in case there's DB calls or anything blocking in `unsubscribed`.
      # Using Tasker allows us to test this in a spec.
      Tasker.in(0.seconds) do
        stale.each do |channel|
          channel.unsubscribed
        rescue e : Exception
          Cable.settings.on_error.call(e, "Exception: #{e.message} -> Cable::Server#send_to_channels(stale channel unsubscribed)", channel.connection)
        end
      end
    end

    private def process_subscribed_messages
      server = self
      spawn(name: "Cable::Server - process_subscribed_messages") do
        while received = fiber_channel.receive?
          channel, message = received
          if channel.starts_with?("cable_internal")
            identifier = channel.split('/').last
            server.find_connection_identifiers(identifier).each do |connection_identifier|
              server.send_to_internal_connections(connection_identifier, message)
            end
          else
            server.send_to_channels(channel, message)
          end
          Cable::Logger.debug { "Cable::Server#process_subscribed_messages channel:#{channel} message:#{message}" }
        end
      end
    end

    # Connection ids are "<identifier>-<uuid>", so match the separator too ("1" must not match "12-...")
    protected def find_connection_identifiers(identifier : String) : Array(String)
      @connections_mutex.synchronize do
        @connections.keys.select { |key| key == identifier || key.starts_with?("#{identifier}-") }
      end
    end

    private def subscribe
      spawn(name: "Cable::Server - subscribe") do
        backend.open_subscribe_connection("_internal")
      end
    end
  end
end
