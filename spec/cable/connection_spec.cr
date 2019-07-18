require "../spec_helper"

describe Cable::Connection do
  it "matches the right route" do
    connect do |connection, socket|
    end
  end

  describe "#subscribe" do
    it "accepts" do
      connect do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => "{\"channel\":\"ChatChannel\",\"params\":{\"room\":\"1\"}}"}.to_json)
        sleep 0.001

        socket.messages.size.should eq(1)
        socket.messages[0].should eq({"type" => "confirm_subscription", "identifier" => "{\"channel\":\"ChatChannel\",\"params\":{\"room\":\"1\"}}"}.to_json)

        Cable::Logger.messages.size.should eq(2)
        Cable::Logger.messages[0].should eq("ChatChannel is streaming from chat_1")
        Cable::Logger.messages[1].should eq("ChatChannel is transmitting the subscription confirmation")
      end
    end
  end

  describe "#message" do
    it "ignore a message for a non valid channel" do
      connect do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => {channel: "ChatChannel", params: {room: "1"}}.to_json}.to_json)
        connection.receive({"command" => "message", "identifier" => "{\"channel\":\"UnknownChannel\",\"params\":{\"room\":\"1\"}}", "data" => "{\"invite_id\":\"3\",\"action\":\"invite\"}"}.to_json)
        sleep 0.001

        socket.messages.size.should eq(1)
        socket.messages[0].should eq({"type" => "confirm_subscription", "identifier" => "{\"channel\":\"ChatChannel\",\"params\":{\"room\":\"1\"}}"}.to_json)

        Cable::Logger.messages.size.should eq(2)
        Cable::Logger.messages[0].should eq("ChatChannel is streaming from chat_1")
        Cable::Logger.messages[1].should eq("ChatChannel is transmitting the subscription confirmation")
      end
    end

    it "receives a message and send to Channel#receive" do
      connect do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => "{\"channel\":\"ChatChannel\",\"params\":{\"room\":\"1\"}}"}.to_json)
        connection.receive({"command" => "message", "identifier" => "{\"channel\":\"ChatChannel\",\"params\":{\"room\":\"1\"}}", "data" => {message: "Hello"}.to_json}.to_json)
        sleep 0.001

        socket.messages.size.should eq(2)
        socket.messages[0].should eq({"type" => "confirm_subscription", "identifier" => "{\"channel\":\"ChatChannel\",\"params\":{\"room\":\"1\"}}"}.to_json)
        socket.messages[1].should eq({"identifier" => "{\"channel\":\"ChatChannel\",\"params\":{\"room\":\"1\"}}", "message" => {message: "Hello", current_user: ""}}.to_json)

        Cable::Logger.messages.size.should eq(5)
        Cable::Logger.messages[0].should eq("ChatChannel is streaming from chat_1")
        Cable::Logger.messages[1].should eq("ChatChannel is transmitting the subscription confirmation")
        Cable::Logger.messages[2].should eq("ChatChannel#receive({\"message\":\"Hello\"})")
        Cable::Logger.messages[3].should eq("[ActionCable] Broadcasting to String: {\"message\" => \"Hello\", \"current_user\" => \"\"}")
        Cable::Logger.messages[4].should eq("ChatChannel transmitting {\"message\":\"Hello\",\"current_user\":\"\"} (via streamed from chat_1)")
      end
    end

    it "receives a message with an action key and sends to Channel#Perform" do
      connect do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => "{\"channel\":\"ChatChannel\",\"params\":{\"room\":\"1\"}}"}.to_json)
        connection.receive({"command" => "message", "identifier" => "{\"channel\":\"ChatChannel\",\"params\":{\"room\":\"1\"}}", "data" => "{\"invite_id\":\"4\",\"action\":\"invite\"}"}.to_json)
        sleep 0.001

        socket.messages.size.should eq(2)
        socket.messages[0].should eq({"type" => "confirm_subscription", "identifier" => "{\"channel\":\"ChatChannel\",\"params\":{\"room\":\"1\"}}"}.to_json)
        socket.messages[1].should eq({"identifier" => "{\"channel\":\"ChatChannel\",\"params\":{\"room\":\"1\"}}", "message" => {"performed" => "invite", "params" => "4"}}.to_json)

        Cable::Logger.messages.size.should eq(5)
        Cable::Logger.messages[0].should eq("ChatChannel is streaming from chat_1")
        Cable::Logger.messages[1].should eq("ChatChannel is transmitting the subscription confirmation")
        Cable::Logger.messages[2].should eq("ChatChannel#perform(invite, {\"invite_id\" => \"4\"})")
        Cable::Logger.messages[3].should eq("[ActionCable] Broadcasting to String: {\"performed\" => \"invite\", \"params\" => \"4\"}")
        Cable::Logger.messages[4].should eq("ChatChannel transmitting {\"performed\":\"invite\",\"params\":\"4\"} (via streamed from chat_1)")
      end
    end
  end

  describe "#broadcast_to" do
    it "sends the broadcasted message" do
      connect do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => "{\"channel\":\"ChatChannel\",\"params\":{\"room\":\"1\"}}"}.to_json)
        connection.broadcast_to(ConnectionTest::CHANNELS["1"]["{\"channel\":\"ChatChannel\",\"params\":{\"room\":\"1\"}}"], {hello: "Broadcast!"}.to_json)
        sleep 0.001

        socket.messages.size.should eq(2)
        socket.messages[0].should eq({"type" => "confirm_subscription", "identifier" => "{\"channel\":\"ChatChannel\",\"params\":{\"room\":\"1\"}}"}.to_json)
        socket.messages[1].should eq({identifier: "{\"channel\":\"ChatChannel\",\"params\":{\"room\":\"1\"}}", message: {hello: "Broadcast!"}}.to_json)

        Cable::Logger.messages.size.should eq(3)
        Cable::Logger.messages[0].should eq("ChatChannel is streaming from chat_1")
        Cable::Logger.messages[1].should eq("ChatChannel is transmitting the subscription confirmation")
        Cable::Logger.messages[2].should eq("ChatChannel transmitting {\"hello\":\"Broadcast!\"} (via streamed from chat_1)")
      end
    end
  end

  describe ".broadcast_to" do
    it "sends the broadcasted message" do
      connect do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => "{\"channel\":\"ChatChannel\",\"params\":{\"room\":\"1\"}}"}.to_json)
        ConnectionTest.broadcast_to("chat_1", {hello: "Broadcast!"}.to_json)
        sleep 0.001

        socket.messages.size.should eq(2)
        socket.messages[0].should eq({"type" => "confirm_subscription", "identifier" => "{\"channel\":\"ChatChannel\",\"params\":{\"room\":\"1\"}}"}.to_json)
        socket.messages[1].should eq({identifier: "{\"channel\":\"ChatChannel\",\"params\":{\"room\":\"1\"}}", message: {hello: "Broadcast!"}}.to_json)

        Cable::Logger.messages.size.should eq(3)
        Cable::Logger.messages[0].should eq("ChatChannel is streaming from chat_1")
        Cable::Logger.messages[1].should eq("ChatChannel is transmitting the subscription confirmation")
        Cable::Logger.messages[2].should eq("ChatChannel transmitting {\"hello\":\"Broadcast!\"} (via streamed from chat_1)")
      end
    end
  end
end

def builds_request
  headers = HTTP::Headers{
    "Upgrade"                => "websocket",
    "Connection"             => "Upgrade",
    "Sec-WebSocket-Key"      => "OqColdEJm3i9e/EqMxnxZw==",
    "Sec-WebSocket-Protocol" => "actioncable-v1-json, actioncable-unsupported",
    "Sec-WebSocket-Version"  => "13",
  }
  request = HTTP::Request.new("GET", "#{Cable.settings.route}?token=1", headers)
end

private class DummySocket < HTTP::WebSocket
  getter messages : Array(String) = Array(String).new

  def send(message)
    @messages << message
  end
end

private class ConnectionTest < Cable::Connection
  def connect
    self.current_user = user_id
  end
end

def connect(&block)
  socket = DummySocket.new(IO::Memory.new)
  connection = ConnectionTest.new(builds_request, socket)

  yield connection, socket

  connection.close
end
