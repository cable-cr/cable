require "../spec_helper"

describe Cable::Handler do
  describe "basic handling" do
    it "matches the right route" do
      handler = Cable::Handler(ApplicationCable::Connection).new
      request = HTTP::Request.new("GET", "#{Cable.settings.route}?test_token=1", headers)

      io_with_context = create_ws_request_and_return_io_and_context(handler, request)[0]
      io_with_context.to_s.should eq("HTTP/1.1 101 Switching Protocols\r\nSec-WebSocket-Protocol: actioncable-v1-json\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: 6x90CSU0y750nc+5Do8J0YjG7lM=\r\n\r\n")
    end

    it "allows you to remove undesired actioncable headers" do
      Cable.settings.disable_sec_websocket_protocol_header = true
      handler = Cable::Handler(ApplicationCable::Connection).new
      request = HTTP::Request.new("GET", "#{Cable.settings.route}?test_token=1", headers_without_sec_websocket_protocol)

      io_with_context = create_ws_request_and_return_io_and_context(handler, request)[0]
      io_with_context.to_s.should eq("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: 6x90CSU0y750nc+5Do8J0YjG7lM=\r\n\r\n")
      Cable.settings.disable_sec_websocket_protocol_header = false
    end

    it "starts the web pinger" do
      Cable::WebsocketPinger.run_every(0.001) do
        address_chan = start_server
        listen_address = address_chan.receive
        ws2 = HTTP::WebSocket.new("ws://#{listen_address}/updates?test_token=1")

        initialized = false
        ws2.on_message do |str|
          if initialized
            str.match(/\{\"type\":\"ping\",\"message\":[0-9]{10}\}/).should be_truthy
            ws2.close
          else
            str.should eq({type: "welcome"}.to_json)
            initialized = true
          end
        end

        ws2.run
      end
    end
  end

  describe "subscribe to channel" do
    it "subscribes" do
      address_chan = start_server
      listen_address = address_chan.receive

      ws2 = HTTP::WebSocket.new("ws://#{listen_address}/updates?test_token=1")

      Cable.server.connections.size.should eq(1)
      Cable.server.active_connections_for("1").size.should eq(1)
      Cable.server.subscribed_channels_for("1").size.should eq(0)

      messages = [
        {type: "welcome"}.to_json,
        {type: "confirm_subscription", identifier: {channel: "ChatChannel", room: "1"}.to_json}.to_json,
      ]
      seq = 0
      ws2.on_message do |str|
        str.should eq(messages[seq])
        seq += 1
        ws2.close if seq >= messages.size
      end
      ws2.on_close do |code, _reason|
        code.should eq(HTTP::WebSocket::CloseCode::AbnormalClosure)
      end
      ws2.send({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)

      ws2.run

      Cable.server.connections.size.should eq(1)
      Cable.server.active_connections_for("1").size.should eq(1)
      Cable.server.subscribed_channels_for("1").size.should eq(1)
    end

    it "malformed data from client" do
      address_chan = start_server
      listen_address = address_chan.receive

      ws2 = HTTP::WebSocket.new("ws://#{listen_address}/updates?test_token=1")

      Cable.server.connections.size.should eq(1)

      # to avoid IO::Error from mock client connection failure
      begin
        # invalid identifier json string
        ws2.send({"command" => "subscribe", "identifier" => "{\"channel\"\"ChatChannel\",\"room\":\"1\"}"}.to_json)
        ws2.run
      rescue
      end

      Cable.server.connections.size.should eq(0)
    end

    it "malformed keys from client" do
      address_chan = start_server
      listen_address = address_chan.receive

      ws2 = HTTP::WebSocket.new("ws://#{listen_address}/updates?test_token=1")

      Cable.server.connections.size.should eq(1)

      # to avoid IO::Error from mock client connection failure
      begin
        # typo in command vs commands
        ws2.send({"commands" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
        ws2.run
      rescue
      end

      Cable.server.connections.size.should eq(0)
    end

    it "reports errors" do
      FakeExceptionService.size.should eq(0)

      address_chan = start_server
      listen_address = address_chan.receive

      ws2 = HTTP::WebSocket.new("ws://#{listen_address}/updates?test_token=1")

      Cable.server.connections.size.should eq(1)

      # to avoid IO::Error from mock client connection failure
      begin
        # typo in command vs commands
        ws2.send({"commands" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
        ws2.run
      rescue
      end

      FakeExceptionService.size.should eq(1)
      FakeExceptionService.exceptions.first.keys.first.should eq("Cable::Handler#socket.on_message")
      FakeExceptionService.exceptions.first.values.first.class.should eq(JSON::SerializableError)
    end

    it "rejected" do
      address_chan = start_server
      listen_address = address_chan.receive

      ws2 = HTTP::WebSocket.new("ws://#{listen_address}/updates?test_token=reject")

      # we never get a connection from the server
      # its rejected before we get a chance to send a message
      Cable.server.connections.size.should eq(0)

      # to avoid IO::Error from mock client connection failure
      begin
        ws2.run
      rescue
      end

      # should be zero connections open
      Cable.server.connections.size.should eq(0)
    end
  end

  describe "receive message from client" do
    it "receives the message" do
      address_chan = start_server
      listen_address = address_chan.receive

      ws2 = HTTP::WebSocket.new("ws://#{listen_address}/updates?test_token=1")

      messages = [
        {type: "welcome"}.to_json,
        {type: "confirm_subscription", identifier: {channel: "ChatChannel", room: "1"}.to_json}.to_json,
        {identifier: {channel: "ChatChannel", room: "1"}.to_json, message: {message: "test", current_user: "1"}}.to_json,
      ]
      seq = 0
      ping_seq = 0
      ws2.on_message do |str|
        if str.match(/\{"type":"ping","message":[0-9]{8,12}\}/) && ping_seq < 2
          ping_seq += 1
          next
        end
        str.should eq(messages[seq])
        seq += 1
        ws2.close if seq >= messages.size
      end
      # App.cable.subscriptions.create({ channel: "ChatChannel", params: {room: "1"}});
      ws2.send({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)

      # wait server subscribe to channel
      # how can we ensure it was subscribed and avoid this sleep?
      sleep 200.milliseconds

      # App.cable.subscriptions.subscriptions[0].send({message: "test"})
      ws2.send({"command" => "message", "identifier" => {channel: "ChatChannel", room: "1"}.to_json, "data" => {message: "test"}.to_json}.to_json)

      ws2.run
    end
  end

  describe "server broadcast to channels" do
    it "sends and clients receives the message" do
      address_chan = start_server
      listen_address = address_chan.receive

      ws2 = HTTP::WebSocket.new("ws://#{listen_address}/updates?test_token=1")

      messages = [
        {type: "welcome"}.to_json,
        {type: "confirm_subscription", identifier: {channel: "ChatChannel", room: "1"}.to_json}.to_json,
        {identifier: {channel: "ChatChannel", room: "1"}.to_json, message: {message: "from Ruby!", current_user: "1"}}.to_json,
      ]
      seq = 0
      ws2.on_message do |str|
        # This is to simulate one broadcast from server, so we `ws2.run` and loose control of the flow
        # this way we are simulating a broadcast while the use is connected
        # before `ws2.close`
        if seq == 0
          # this is a sleep to avoid publishing before channel hasn't subscribed
          sleep 200.milliseconds
          Cable.server.publish("chat_1", {"message" => "from Ruby!", "current_user" => "1"}.to_json)
        end
        str.should eq(messages[seq])
        seq += 1
        ws2.close if seq >= messages.size
      end
      # App.cable.subscriptions.create({ channel: "ChatChannel", params: {room: "1"}});
      ws2.send({command: "subscribe", identifier: {channel: "ChatChannel", room: "1"}.to_json}.to_json)
      ws2.run
    end
  end

  describe "performs" do
    it "server receive commands and performs an action" do
      address_chan = start_server
      listen_address = address_chan.receive

      ws2 = HTTP::WebSocket.new("ws://#{listen_address}/updates?test_token=1")

      messages = [
        {type: "welcome"}.to_json,
        {type: "confirm_subscription", identifier: {channel: "ChatChannel", room: "1"}.to_json}.to_json,
        {identifier: {channel: "ChatChannel", room: "1"}.to_json, message: {performed: "invite", params: "3"}}.to_json,
      ]
      seq = 0
      ws2.on_message do |str|
        str.should eq(messages[seq])
        seq += 1
        ws2.close if seq >= messages.size
      end
      # App.cable.subscriptions.create({ channel: "ChatChannel", params: {room: "1"}});
      ws2.send({command: "subscribe", identifier: {channel: "ChatChannel", room: "1"}.to_json}.to_json)

      # wait server subscribe to channel
      # how can we ensure it was subscribed and avoid this sleep?
      sleep 100.milliseconds

      # App.cable.subscriptions.subscriptions[0].perform("invite", {invite_id: "3"});
      ws2.send({command: "message", identifier: {channel: "ChatChannel", room: "1"}.to_json, data: {invite_id: "3", action: "invite"}.to_json}.to_json)
      ws2.run
    end
  end

  describe "the error handling" do
    it "doesn't match the wrong route" do
      handler = Cable::Handler(ApplicationCable::Connection).new
      request = HTTP::Request.new("GET", "/unknown_route?test_token=1", headers)

      io_with_context = create_ws_request_and_return_io_and_context(handler, request)[0]
      io_with_context.to_s.should contain("404 Not Found")
    end

    it "doesn't upgrade with wrong headers (without Upgrade header)" do
      handler = Cable::Handler(ApplicationCable::Connection).new
      headers_without_upgrade = headers
      headers_without_upgrade.delete("Upgrade")
      request = HTTP::Request.new("GET", "/unknown_route?test_token=1", headers_without_upgrade)

      io_with_context = create_ws_request_and_return_io_and_context(handler, request)[0]
      io_with_context.to_s.should contain("404 Not Found")
    end

    it "doesn't upgrade with wrong headers (without Connection header)" do
      handler = Cable::Handler(ApplicationCable::Connection).new
      headers_without_connection = headers
      headers_without_connection.delete("Connection")
      request = HTTP::Request.new("GET", "/unknown_route?test_token=1", headers_without_connection)

      io_with_context = create_ws_request_and_return_io_and_context(handler, request)[0]
      io_with_context.to_s.should contain("404 Not Found")
    end

    it "restarts the server if too many errors" do
      address_chan = start_server
      listen_address = address_chan.receive

      # no errors
      Cable.server.errors.should eq(0)

      # connect
      Cable.server.connections.size.should eq(0)
      ws2 = HTTP::WebSocket.new("ws://#{listen_address}/updates?test_token=ws2")
      Cable.server.connections.size.should eq(1)
      ws3 = HTTP::WebSocket.new("ws://#{listen_address}/updates?test_token=ws3")
      Cable.server.connections.size.should eq(2)
      ws4 = HTTP::WebSocket.new("ws://#{listen_address}/updates?test_token=ws4")
      Cable.server.connections.size.should eq(3)
      _ws5 = HTTP::WebSocket.new("ws://#{listen_address}/updates?test_token=ws5")
      Cable.server.connections.size.should eq(4)

      connections = Cable.server.connections.keys
      connections.any?(&.starts_with?("ws2")).should eq(true)
      connections.any?(&.starts_with?("ws3")).should eq(true)
      connections.any?(&.starts_with?("ws4")).should eq(true)
      connections.any?(&.starts_with?("ws5")).should eq(true)

      messages = [
        {type: "welcome"}.to_json,
        {type: "confirm_subscription", identifier: {channel: "ChatChannel", room: "1"}.to_json}.to_json,
        {identifier: {channel: "ChatChannel", room: "1"}.to_json, message: {message: "test", current_user: "ws2"}}.to_json,
      ]
      seq = 0
      ping_seq = 0
      ws2.on_message do |str|
        if str.match(/\{"type":"ping","message":[0-9]{8,12}\}/) && ping_seq < 2
          ping_seq += 1
          next
        end
        str.should eq(messages[seq])
        seq += 1
        ws2.close if seq >= messages.size
      end
      # subscribe
      ws2.send({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)

      sleep 200.milliseconds

      # send message
      ws2.send({"command" => "message", "identifier" => {channel: "ChatChannel", room: "1"}.to_json, "data" => {message: "test"}.to_json}.to_json)
      # raise error
      ws2.send({"command" => "message", "identifier" => {channel: "ChatChannel", room: "1"}.to_json, "data" => {message: "raise"}.to_json}.to_json)

      ws2.run

      # 1 error
      Cable.server.errors.should eq(1)

      # connection 1 will be disconnected due to error
      Cable.server.connections.size.should eq(3)
      connections = Cable.server.connections.keys
      connections.any?(&.starts_with?("ws2")).should eq(false)

      messages = [
        {type: "welcome"}.to_json,
        {type: "confirm_subscription", identifier: {channel: "ChatChannel", room: "1"}.to_json}.to_json,
        {identifier: {channel: "ChatChannel", room: "1"}.to_json, message: {message: "test", current_user: "ws3"}}.to_json,
      ]
      seq = 0
      ping_seq = 0
      ws3.on_message do |str|
        if str.match(/\{"type":"ping","message":[0-9]{8,12}\}/) && ping_seq < 2
          ping_seq += 1
          next
        end
        str.should eq(messages[seq])
        seq += 1
        ws3.close if seq >= messages.size
      end
      # subscribe
      ws3.send({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)

      sleep 200.milliseconds

      # send message
      ws3.send({"command" => "message", "identifier" => {channel: "ChatChannel", room: "1"}.to_json, "data" => {message: "test"}.to_json}.to_json)
      # raise error
      ws3.send({"command" => "message", "identifier" => {channel: "ChatChannel", room: "1"}.to_json, "data" => {message: "raise"}.to_json}.to_json)

      ws3.run

      # 2 errors
      Cable.server.errors.should eq(2)

      # connection 1 will be disconnected due to error
      Cable.server.connections.size.should eq(2)
      connections = Cable.server.connections.keys
      connections.any?(&.starts_with?("ws3")).should eq(false)

      messages = [
        {type: "welcome"}.to_json,
        {type: "confirm_subscription", identifier: {channel: "ChatChannel", room: "1"}.to_json}.to_json,
        {identifier: {channel: "ChatChannel", room: "1"}.to_json, message: {message: "test", current_user: "ws3"}}.to_json,
      ]
      seq = 0
      ping_seq = 0
      ws4.on_message do |str|
        if str.match(/\{"type":"ping","message":[0-9]{8,12}\}/) && ping_seq < 2
          ping_seq += 1
          next
        end
        str.should eq(messages[seq])
        seq += 1
        ws4.close if seq >= messages.size
      end
      # subscribe
      ws4.send({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)

      sleep 200.milliseconds

      # send message
      ws4.send({"command" => "message", "identifier" => {channel: "ChatChannel", room: "1"}.to_json, "data" => {message: "test"}.to_json}.to_json)
      # raise error
      ws4.send({"command" => "message", "identifier" => {channel: "ChatChannel", room: "1"}.to_json, "data" => {message: "raise"}.to_json}.to_json)

      ws4.run

      sleep 200.milliseconds

      # we should have 1 connectoon ws5 open
      # but since the server restarted due to volume of errors
      # all connections will be closed
      # errors will be reset
      Cable.server.errors.should eq(0)
      Cable.server.connections.size.should eq(0)
    end
  end
end

# Thanks @kemalcr
private def create_ws_request_and_return_io_and_context(handler, request)
  io = IO::Memory.new
  response = HTTP::Server::Response.new(io)
  context = HTTP::Server::Context.new(request, response)
  begin
    handler.call context
  rescue IO::Error
    # Raises because the IO::Memory is empty
  end
  io.rewind
  {io, context}
end

private def start_server
  address_chan = Channel(Socket::IPAddress).new

  spawn do
    # Make pinger real fast so we don't need to wait
    http_server = HTTP::Server.new([Cable::Handler(ApplicationCable::Connection).new])
    address = http_server.bind_unused_port
    address_chan.send(address)
    http_server.listen
  end

  address_chan
end

private def headers
  HTTP::Headers{
    "Upgrade"                => "websocket",
    "Connection"             => "Upgrade",
    "Sec-WebSocket-Key"      => "OqColdEJm3i9e/EqMxnxZw==",
    "Sec-WebSocket-Protocol" => "actioncable-v1-json, actioncable-unsupported",
    "Sec-WebSocket-Version"  => "13",
  }
end

private def headers_without_sec_websocket_protocol
  HTTP::Headers{
    "Upgrade"               => "websocket",
    "Connection"            => "Upgrade",
    "Sec-WebSocket-Key"     => "OqColdEJm3i9e/EqMxnxZw==",
    "Sec-WebSocket-Version" => "13",
  }
end
