require "http/server"

module Cable
  class Handler(T)
    include HTTP::Handler

    def on_error(&@on_error : Exception ->) : self
      self
    end

    def call(context)
      return call_next(context) unless ws_route_found?(context) && websocket_upgrade_request?(context)

      remote_address = context.request.remote_address
      path = context.request.path
      Cable::Logger.info { "Started GET \"#{path}\" [WebSocket] for #{remote_address} at #{Time.utc}" }

      unless Cable.settings.disable_sec_websocket_protocol_header
        context.response.headers["Sec-WebSocket-Protocol"] = "actioncable-v1-json"
      end

      ws = HTTP::WebSocketHandler.new do |socket, _context|
        connection = T.new(context.request, socket)
        connection_id = connection.connection_identifier

        # we should not add any connections which have been rejected
        if connection.connection_rejected?
          Cable::Logger.info { "Connection rejected" }
        else
          Cable.server.add_connection(connection)
        end

        # Send welcome message to the client
        socket.send({type: Cable.message(:welcome)}.to_json)

        ws_pinger = Cable::WebsocketPinger.build(socket)

        socket.on_ping do
          socket.pong context.request.path
          Cable::Logger.debug { "Ping received" }
        end

        # Handle incoming message and echo back to the client
        socket.on_message do |message|
          begin
            connection.receive(message)
          rescue e : KeyError
            # handle unknown/malformed messages
            socket.close(HTTP::WebSocket::CloseCode::InvalidFramePayloadData, "Invalid message")
            Cable::Logger.error { "KeyError Exception: #{e.message}" }
          rescue e : Cable::Connection::UnathorizedConnectionException
            # do nothing, this is planned
            socket.close(HTTP::WebSocket::CloseCode::NormalClosure, "Farewell")
          rescue e : IO::Error
            Cable::Logger.error { "#{e.class.name} Exception: #{e.message} -> #{self.class.name}#call { socket.on_message(message) }" }
            # Redis may have some error, restart Cable
            socket.close(HTTP::WebSocket::CloseCode::NormalClosure, "Farewell")
            Cable.restart
          rescue e : Exception
            socket.close(HTTP::WebSocket::CloseCode::InternalServerError, "Internal Server Error")
            Cable::Logger.error { "Exception: #{e.message}" }
          end
        end

        socket.on_close do
          ws_pinger.stop
          Cable.server.remove_connection(connection_id)
          Cable::Logger.info { "Finished \"#{path}\" [WebSocket] for #{remote_address} at #{Time.utc}" }
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
