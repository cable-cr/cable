require "http/server"

module Cable
  class Handler(T)
    include HTTP::Handler

    def call(context)
      return call_next(context) unless ws_route_found?(context) && websocket_upgrade_request?(context)

      remote_address = context.request.remote_address
      path = context.request.path
      Cable::Logger.info { "Started GET \"#{path}\" [WebSocket] for #{remote_address} at #{Time.utc}" }

      unless Cable.settings.disable_sec_websocket_protocol_header
        context.response.headers["Sec-WebSocket-Protocol"] = "actioncable-v1-json"
      end

      ws = HTTP::WebSocketHandler.new do |socket, ws_ctx|
        connection = T.new(ws_ctx.request, socket)
        connection_id = connection.connection_identifier

        # we should not add any connections which have been rejected
        Cable.server.add_connection(connection) unless connection.connection_rejected?

        # Send welcome message to the client
        socket.send({type: Cable.message(:welcome)}.to_json)

        ws_pinger = Cable::WebsocketPinger.build(socket)

        socket.on_ping do
          socket.pong ws_ctx.request.path
          Cable::Logger.debug { "Ping received" }
        end

        # Handle incoming message and echo back to the client
        #
        # **Exceptions**
        # turns out, if you close socket in this block
        # the socket.on_close blocked is not called 100% of the time
        # so we need to do it manually
        socket.on_message do |message|
          begin
            connection.receive(message)
          rescue e : KeyError | JSON::ParseException | JSON::SerializableError
            # handle unknown/malformed messages
            socket.close(HTTP::WebSocket::CloseCode::InvalidFramePayloadData, "Invalid message")
            Cable.server.remove_connection(connection_id)
            Cable.settings.on_error.call(e, "Cable::Handler#socket.on_message")
          rescue e : Cable::Connection::UnathorizedConnectionException
            # handle unauthorized connections
            # no need to log them
            socket.close(HTTP::WebSocket::CloseCode::NormalClosure, "Farewell")
            # most of the time, we will have already removed the connection
            # since the connection is rejected before any messages are received
            # but just in case, we will try remove it anyways
            Cable.server.remove_connection(connection_id)
          rescue e : Exception
            # handle all other exceptions
            socket.close(HTTP::WebSocket::CloseCode::InternalServerError, "Internal Server Error")
            Cable.server.remove_connection(connection_id)
            # handle restart
            Cable.server.count_error!
            Cable.restart if Cable.server.restart?
            Cable.settings.on_error.call(e, "Cable::Handler#socket.on_message")
          end
        end

        socket.on_close do
          ws_pinger.stop
          Cable.server.remove_connection(connection_id)
          Cable::Logger.info { "Finished \"#{path}\" [WebSocket] for #{remote_address} at #{Time.utc}" }
        end
      rescue e : Exception
        Cable.settings.on_error.call(e, "Cable::Handler#call -> HTTP::WebSocketHandler")
        raise e
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
