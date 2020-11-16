require "http/server"

# require "http/handler"

module Cable
  class Handler
    include HTTP::Handler

    def initialize(@connection_class : Cable::Connection.class)
    end

    def call(context)
      return call_next(context) unless ws_route_found?(context) && websocket_upgrade_request?(context)

      remote_address = context.request.remote_address
      path = context.request.path
      Cable::Logger.info "Started GET \"#{path}\" [WebSocket] for #{remote_address} at #{Time.utc.to_s}"

      context.response.headers["Sec-WebSocket-Protocol"] = "actioncable-v1-json"

      ws = HTTP::WebSocketHandler.new do |socket, context|
        socket.on_ping { socket.pong context.request.path }
        connection = @connection_class.new(context.request, socket)

        # Send welcome message to the client
        socket.send({type: "welcome"}.to_json)

        Cable::WebsocketPinger.build(socket)

        # Handle incoming message and echo back to the client
        socket.on_message do |message|
          begin
            connection.receive(message)
          rescue e : Exception
            Cable::Logger.info "Exception: #{e.message}"
          end
        end

        socket.on_close do
          #connection.close
          Cable::Logger.info "Finished \"#{path}\" [WebSocket] for #{remote_address} at #{Time.utc.to_s}"
        end
      end

      Cable::Logger.info "Successfully upgraded to WebSocket (REQUEST_METHOD: GET, HTTP_CONNECTION: Upgrade, HTTP_UPGRADE: websocket)"
      content = ws.call(context)

      # These cause a websocket issue with `One or more reserved bits are on: reserved1 = 1, reserved2 = 0, reserved3 = 0`
      #content.as(Proc(IO, Nil)).call(context.response.output)
      #context.response.print(content)
      context
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
