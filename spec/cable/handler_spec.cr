require "../spec_helper"

describe Cable::Handler do
  describe "basic handling" do
    it "matches the right route" do
      handler = Cable::Handler.new(ApplicationCable::Connection)
      request = HTTP::Request.new("GET", "#{Cable.settings.route}?test_token=1", headers)

      io_with_context = create_ws_request_and_return_io_and_context(handler, request)[0]
      io_with_context.to_s.should eq("HTTP/1.1 101 Switching Protocols\r\nSec-WebSocket-Protocol: actioncable-v1-json\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: 6x90CSU0y750nc+5Do8J0YjG7lM=\r\n\r\n\x81\u0012{\"type\":\"welcome\"}")
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
            str.should eq("{\"type\":\"welcome\"}")
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

      messages = [
        %({"type":"welcome"}),
        %({"type":"confirm_subscription","identifier":"{\\"channel\\":\\"ChatChannel\\",\\"room\\":\\"1\\"}"}),
      ]
      seq = 0
      ws2.on_message do |str|
        str.should eq(messages[seq])
        seq += 1
        ws2.close if seq >= messages.size
      end
      # App.cable.subscriptions.create({ channel: "ChatChannel", params: {room: "1"}});
      ws2.send({"command" => "subscribe", "identifier" => "{\"channel\":\"ChatChannel\",\"room\":\"1\"}"}.to_json)

      ws2.run
    end
  end

  describe "receive message from client" do
    it "receives the message" do
      address_chan = start_server
      listen_address = address_chan.receive

      ws2 = HTTP::WebSocket.new("ws://#{listen_address}/updates?test_token=1")

      messages = [
        "{\"type\":\"welcome\"}",
        "{\"type\":\"confirm_subscription\",\"identifier\":\"{\\\"channel\\\":\\\"ChatChannel\\\",\\\"room\\\":\\\"1\\\"}\"}",
        "{\"identifier\":\"{\\\"channel\\\":\\\"ChatChannel\\\",\\\"room\\\":\\\"1\\\"}\",\"message\":{\"message\":\"test\",\"current_user\":\"1\"}}",
      ]
      seq = 0
      ws2.on_message do |str|
        str.should eq(messages[seq])
        seq += 1
        ws2.close if seq >= messages.size
      end
      # App.cable.subscriptions.create({ channel: "ChatChannel", params: {room: "1"}});
      ws2.send({"command" => "subscribe", "identifier" => "{\"channel\":\"ChatChannel\",\"room\":\"1\"}"}.to_json)
      # App.cable.subscriptions.subscriptions[0].send({message: "test"})
      ws2.send({"command" => "message", "identifier" => "{\"channel\":\"ChatChannel\",\"room\":\"1\"}", "data" => "{\"message\":\"test\"}"}.to_json)

      ws2.run
    end
  end

  describe "server broadcast to channels" do
    it "sends and clients receives the message" do
      address_chan = start_server
      listen_address = address_chan.receive

      ws2 = HTTP::WebSocket.new("ws://#{listen_address}/updates?test_token=1")

      messages = [
        "{\"type\":\"welcome\"}",
        "{\"type\":\"confirm_subscription\",\"identifier\":\"{\\\"channel\\\":\\\"ChatChannel\\\",\\\"room\\\":\\\"1\\\"}\"}",
        "{\"identifier\":\"{\\\"channel\\\":\\\"ChatChannel\\\",\\\"room\\\":\\\"1\\\"}\",\"message\":{\"message\":\"from Ruby!\",\"current_user\":\"1\"}}",
      ]
      seq = 0
      ws2.on_message do |str|
        # This is to simulate one broadcast from server, so we `ws2.run` and loose control of the flow
        # this way we are simulating a broadcast while the use is connected
        # before `ws2.close`
        ChatChannel.broadcast_to("chat_1", {"message" => "from Ruby!", "current_user" => "1"}) if seq == 0
        str.should eq(messages[seq])
        seq += 1
        ws2.close if seq >= messages.size
      end
      # App.cable.subscriptions.create({ channel: "ChatChannel", params: {room: "1"}});
      ws2.send({"command" => "subscribe", "identifier" => "{\"channel\":\"ChatChannel\",\"room\":\"1\"}"}.to_json)
      ws2.run
    end
  end

  describe "performs" do
    it "server receive commands and performs an action" do
      address_chan = start_server
      listen_address = address_chan.receive

      ws2 = HTTP::WebSocket.new("ws://#{listen_address}/updates?test_token=1")

      messages = [
        "{\"type\":\"welcome\"}",
        "{\"type\":\"confirm_subscription\",\"identifier\":\"{\\\"channel\\\":\\\"ChatChannel\\\",\\\"room\\\":\\\"1\\\"}\"}",
        "{\"identifier\":\"{\\\"channel\\\":\\\"ChatChannel\\\",\\\"room\\\":\\\"1\\\"}\",\"message\":{\"performed\":\"invite\",\"params\":\"3\"}}",
      ]
      seq = 0
      ws2.on_message do |str|
        str.should eq(messages[seq])
        seq += 1
        ws2.close if seq >= messages.size
      end
      # App.cable.subscriptions.create({ channel: "ChatChannel", params: {room: "1"}});
      ws2.send({"command" => "subscribe", "identifier" => "{\"channel\":\"ChatChannel\",\"room\":\"1\"}"}.to_json)
      # App.cable.subscriptions.subscriptions[0].perform("invite", {invite_id: "3"});
      ws2.send({"command" => "message", "identifier" => "{\"channel\":\"ChatChannel\",\"room\":\"1\"}", "data" => "{\"invite_id\":\"3\",\"action\":\"invite\"}"}.to_json)
      ws2.run
    end
  end

  describe "the error handling" do
    it "doesn't match the wrong route" do
      handler = Cable::Handler.new(ApplicationCable::Connection)
      request = HTTP::Request.new("GET", "/unknown_route?test_token=1", headers)

      io_with_context = create_ws_request_and_return_io_and_context(handler, request)[0]
      io_with_context.to_s.should eq("HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nContent-Length: 14\r\n\r\n404 Not Found\n")
    end

    it "doesn't upgrade with wrong headers (without Upgrade header)" do
      handler = Cable::Handler.new(ApplicationCable::Connection)
      headers_without_upgrade = headers
      headers_without_upgrade.delete("Upgrade")
      request = HTTP::Request.new("GET", "/unknown_route?test_token=1", headers_without_upgrade)

      io_with_context = create_ws_request_and_return_io_and_context(handler, request)[0]
      io_with_context.to_s.should eq("HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nContent-Length: 14\r\n\r\n404 Not Found\n")
    end

    it "doesn't upgrade with wrong headers (without Connection header)" do
      handler = Cable::Handler.new(ApplicationCable::Connection)
      headers_without_connection = headers
      headers_without_connection.delete("Connection")
      request = HTTP::Request.new("GET", "/unknown_route?test_token=1", headers_without_connection)

      io_with_context = create_ws_request_and_return_io_and_context(handler, request)[0]
      io_with_context.to_s.should eq("HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nContent-Length: 14\r\n\r\n404 Not Found\n")
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

private class ConnectionMock
  INSTANCE = new
  getter closed, received
  @closed : Bool = true
  @received : Array(String) = Array(String).new

  def close
    @closed = true
  end

  def receive(message)
    @received << message
  end

  def reset
    @closed = false
    @received = [] of String
  end
end

private def start_server
  address_chan = Channel(Socket::IPAddress).new

  spawn do
    # Make pinger real fast so we don't need to wait
    http_ref = nil
    http_server = http_ref = HTTP::Server.new([Cable::Handler.new(ApplicationCable::Connection)])
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
