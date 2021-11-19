require "http/server"

module Cable
  class Handler
    include HTTP::Handler

    def initialize(@connection_class : Cable::Connection.class)
    end

    def call(context)
      return call_next(context) unless ws_route_found?(context) && websocket_upgrade_request?(context)

      remote_address = context.request.remote_address
      path = context.request.path
      Cable::Logger.info { "Started GET \"#{path}\" [WebSocket] for #{remote_address} at #{Time.utc.to_s}" }

      unless Cable.settings.disable_sec_websocket_protocol_header
        context.response.headers["Sec-WebSocket-Protocol"] = "actioncable-v1-json"
      end

      ws = HTTP::WebSocketHandler.new do |socket, context|
        connection = @connection_class.new(context.request, socket)
        connection_id = connection.connection_identifier

        # we should not add any connections which have been rejected
        Cable.server.add_connection(connection) unless connection.connection_rejected?

        # Send welcome message to the client
        socket.send({type: "welcome"}.to_json)

        Cable::WebsocketPinger.build(socket)

        socket.on_ping do
          socket.pong context.request.path
          Cable::Logger.debug { "Ping received" }
        end

        # Handle incoming message and echo back to the client
        socket.on_message do |message|
          begin
            connection.receive(message)
          rescue e : Cable::Connection::UnathorizedConnectionException
            # do nothing, this is planned
          rescue e : Exception
            Cable::Logger.error { "Exception: #{e.message}" }
          end
        end

        socket.on_close do
          Cable.server.remove_connection(connection_id)
          Cable::Logger.info { "Finished \"#{path}\" [WebSocket] for #{remote_address} at #{Time.utc.to_s}" }
        end
      end

      Cable::Logger.info { "Successfully upgraded to WebSocket (REQUEST_METHOD: GET, HTTP_CONNECTION: Upgrade, HTTP_UPGRADE: websocket)" }
      ws.call(context)
    end

    private def websocket_upgrade_request?(context)
      return unless upgrade = context.request.headers["Upgrade"]?
      return unless upgrade.compare("websocket", case_insensitive: true) == 0

      context.request.headers.includes_word?("Connection", "Upgrade")
    end

    private def ws_route_found?(context)
      return true if context.request.path === Cable.settings.route
      false
    end
  end
end
