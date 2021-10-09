module Cable
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
    getter connections
    getter redis_subscribe
    getter redis_publish
    getter fiber_channel

    def initialize
      @connections = {} of String => Connection
      @channels = {} of String => Array(Cable::Channel)
      @redis_subscribe = Redis.new(url: Cable.settings.url)
      @redis_publish = Redis.new(url: Cable.settings.url)
      @fiber_channel = ::Channel({String, String}).new
      subscribe
      process_subscribed_messages
    end

    def add_connection(connection)
      connections[connection.connection_identifier] = connection
    end

    def remove_connection(connection_id)
      connection = connections.delete(connection_id)
      if connection.is_a?(Connection)
        connection.close
      end
    end

    def subscribe_channel(channel : Channel, identifier : String)
      if !@channels.has_key?(identifier)
        @channels[identifier] = [] of Cable::Channel
      end

      @channels[identifier] << channel

      request = Redis::Request.new
      request << "subscribe"
      request << identifier
      request_return = redis_subscribe._connection.send(request)
    end

    def unsubscribe_channel(channel : Channel, identifier : String)
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

    def publish(channel, message)
      redis_publish.publish("#{channel}", message)
    end

    def send_to_channels(identifier, message)
      parsed_message = JSON.parse(message)

      if @channels.has_key?(identifier)
        @channels[identifier].each do |channel|
          # TODO: would be nice to have a test where we open two connections
          # close one, and make sure the other one receives the message
          if channel.connection.socket.closed?
            @channels[identifier].delete(channel)
          else
            Cable::Logger.info "#{channel.class} transmitting #{parsed_message} (via streamed from #{channel.stream_identifier})"
            channel.connection.socket.send({
              identifier: channel.identifier,
              message:    parsed_message,
            }.to_json)
          end
        end
      end
    rescue IO::Error
    end

    def debug
      Cable::Logger.debug "-" * 80
      Cable::Logger.debug "Some Good Information"
      Cable::Logger.debug "Connections"
      @connections.each do |k, v|
        Cable::Logger.debug "Connection Key: #{k}"
      end
      Cable::Logger.debug "Channels"
      @channels.each do |k, v|
        Cable::Logger.debug "Channel Key: #{k}"
        Cable::Logger.debug "Channels"
        v.each do |channel|
          Cable::Logger.debug "From Channel: #{channel.connection.connection_identifier}"
          Cable::Logger.debug "Params: #{channel.params}"
          Cable::Logger.debug "ID: #{channel.identifier}"
          Cable::Logger.debug "Stream ID:: #{channel.stream_identifier}"
        end
      end
      Cable::Logger.debug "-" * 80
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
          channel = received[0]
          message = received[1]
          server.send_to_channels(channel, message)
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
            end
          end
        end
      end
    end
  end
end
