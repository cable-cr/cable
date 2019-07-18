require "../spec_helper"

describe Cable::Connection do
  it "matches the right route" do
    connect do |connection, socket|
    end
  end

  describe "#subscribe" do
    it "accepts" do
      connect do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => "{\"channel\":\"ChatChannel\",\"room\":\"1\"}"}.to_json)
        sleep 0.001

        socket.messages.size.should eq(1)
        socket.messages[0].should eq({"type" => "confirm_subscription", "identifier" => "{\"channel\":\"ChatChannel\",\"room\":\"1\"}"}.to_json)

        Cable::Logger.messages.size.should eq(2)
        Cable::Logger.messages[0].should eq("ChatChannel is streaming from chat_1")
        Cable::Logger.messages[1].should eq("ChatChannel is transmitting the subscription confirmation")
      end
    end

    it "accepts without params hash key" do
      connect do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => "{\"channel\":\"ChatChannel\",\"room\":\"1\"}"}.to_json)
        sleep 0.001

        socket.messages.size.should eq(1)
        socket.messages[0].should eq({"type" => "confirm_subscription", "identifier" => "{\"channel\":\"ChatChannel\",\"room\":\"1\"}"}.to_json)

        Cable::Logger.messages.size.should eq(2)
        Cable::Logger.messages[0].should eq("ChatChannel is streaming from chat_1")
        Cable::Logger.messages[1].should eq("ChatChannel is transmitting the subscription confirmation")
      end
    end

    it "accepts with nested hash" do
      connect do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => "{\"channel\":\"ChatChannel\",\"room\":\"1\",\"person\":{\"name\":\"Celso\",\"age\":32,\"boom\":\"boom\"}}"}.to_json)
        sleep 0.001

        socket.messages.size.should eq(1)
        socket.messages[0].should eq({"type" => "confirm_subscription", "identifier" => "{\"channel\":\"ChatChannel\",\"room\":\"1\",\"person\":{\"name\":\"Celso\",\"age\":32,\"boom\":\"boom\"}}"}.to_json)

        Cable::Logger.messages.size.should eq(2)
        Cable::Logger.messages[0].should eq("ChatChannel is streaming from chat_1")
        Cable::Logger.messages[1].should eq("ChatChannel is transmitting the subscription confirmation")
      end
    end
  end

  describe ".identified_by" do
    it "uses the right identifier name for it" do
      connect do |connection, socket|
        connection.identifier.should eq("98")
      end
    end
  end

  describe ".owned_by" do
    it "uses the right identifier name for it" do
      connect do |connection, socket|
        connection.current_user.not_nil!.email.should eq("user98@mail.com")
        connection.organization.not_nil!.name.should eq("Acme Inc.")
      end
    end
  end

  describe "#reject_unauthorized_connection" do
    it "rejects the unauthorized connection" do
      connect(UnauthorizedConnectionTest) do |connection, socket|
        socket.messages.size.should eq(0)

        Cable::Logger.messages.size.should eq(1)
        Cable::Logger.messages[0].should eq("An unauthorized connection attempt was rejected")
        socket.closed?.should be_truthy
      end
    end
  end

  describe "#message" do
    it "ignore a message for a non valid channel" do
      connect do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
        connection.receive({"command" => "message", "identifier" => "{\"channel\":\"UnknownChannel\",\"room\":\"1\"}", "data" => "{\"invite_id\":\"3\",\"action\":\"invite\"}"}.to_json)
        sleep 0.001

        socket.messages.size.should eq(1)
        socket.messages[0].should eq({"type" => "confirm_subscription", "identifier" => "{\"channel\":\"ChatChannel\",\"room\":\"1\"}"}.to_json)

        Cable::Logger.messages.size.should eq(2)
        Cable::Logger.messages[0].should eq("ChatChannel is streaming from chat_1")
        Cable::Logger.messages[1].should eq("ChatChannel is transmitting the subscription confirmation")
      end
    end

    it "receives a message and send to Channel#receive" do
      connect do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => "{\"channel\":\"ChatChannel\",\"room\":\"1\"}"}.to_json)
        connection.receive({"command" => "message", "identifier" => "{\"channel\":\"ChatChannel\",\"room\":\"1\"}", "data" => {message: "Hello"}.to_json}.to_json)
        sleep 0.001

        socket.messages.size.should eq(2)
        socket.messages[0].should eq({"type" => "confirm_subscription", "identifier" => "{\"channel\":\"ChatChannel\",\"room\":\"1\"}"}.to_json)
        socket.messages[1].should eq({"identifier" => "{\"channel\":\"ChatChannel\",\"room\":\"1\"}", "message" => {message: "Hello", current_user: "98"}}.to_json)

        Cable::Logger.messages.size.should eq(5)
        Cable::Logger.messages[0].should eq("ChatChannel is streaming from chat_1")
        Cable::Logger.messages[1].should eq("ChatChannel is transmitting the subscription confirmation")
        Cable::Logger.messages[2].should eq("ChatChannel#receive({\"message\" => \"Hello\"})")
        Cable::Logger.messages[3].should eq("[ActionCable] Broadcasting to chat_1: {\"message\" => \"Hello\", \"current_user\" => \"98\"}")
        Cable::Logger.messages[4].should eq("ChatChannel transmitting {\"message\" => \"Hello\", \"current_user\" => \"98\"} (via streamed from chat_1)")
      end
    end

    it "receives a message with an action key and sends to Channel#Perform" do
      connect do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => "{\"channel\":\"ChatChannel\",\"room\":\"1\"}"}.to_json)
        connection.receive({"command" => "message", "identifier" => "{\"channel\":\"ChatChannel\",\"room\":\"1\"}", "data" => "{\"invite_id\":\"4\",\"action\":\"invite\"}"}.to_json)
        sleep 0.001

        socket.messages.size.should eq(2)
        socket.messages[0].should eq({"type" => "confirm_subscription", "identifier" => "{\"channel\":\"ChatChannel\",\"room\":\"1\"}"}.to_json)
        socket.messages[1].should eq({"identifier" => "{\"channel\":\"ChatChannel\",\"room\":\"1\"}", "message" => {"performed" => "invite", "params" => "4"}}.to_json)

        Cable::Logger.messages.size.should eq(5)
        Cable::Logger.messages[0].should eq("ChatChannel is streaming from chat_1")
        Cable::Logger.messages[1].should eq("ChatChannel is transmitting the subscription confirmation")
        Cable::Logger.messages[2].should eq("ChatChannel#perform(\"invite\", {\"invite_id\" => \"4\"})")
        Cable::Logger.messages[3].should eq("[ActionCable] Broadcasting to chat_1: {\"performed\" => \"invite\", \"params\" => \"4\"}")
        Cable::Logger.messages[4].should eq("ChatChannel transmitting {\"performed\" => \"invite\", \"params\" => \"4\"} (via streamed from chat_1)")
      end
    end
  end

  describe "#broadcast_to" do
    it "sends the broadcasted message" do
      connect do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => "{\"channel\":\"ChatChannel\",\"room\":\"1\"}"}.to_json)
        sleep 0.001
        connection.broadcast_to(ConnectionTest::CHANNELS["98"]["{\"channel\":\"ChatChannel\",\"room\":\"1\"}"], {hello: "Broadcast!"}.to_json)

        socket.messages.size.should eq(2)
        socket.messages[0].should eq({"type" => "confirm_subscription", "identifier" => "{\"channel\":\"ChatChannel\",\"room\":\"1\"}"}.to_json)
        socket.messages[1].should eq({identifier: "{\"channel\":\"ChatChannel\",\"room\":\"1\"}", message: {hello: "Broadcast!"}}.to_json)

        Cable::Logger.messages.size.should eq(3)
        Cable::Logger.messages[0].should eq("ChatChannel is streaming from chat_1")
        Cable::Logger.messages[1].should eq("ChatChannel is transmitting the subscription confirmation")
        Cable::Logger.messages[2].should eq("ChatChannel transmitting {\"hello\" => \"Broadcast!\"} (via streamed from chat_1)")
      end
    end
  end

  describe ".broadcast_to" do
    it "sends the broadcasted message" do
      connect do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => "{\"channel\":\"ChatChannel\",\"room\":\"1\"}"}.to_json)
        ConnectionTest.broadcast_to("chat_1", {hello: "Broadcast!"}.to_json)
        sleep 0.001

        socket.messages.size.should eq(2)
        socket.messages[0].should eq({"type" => "confirm_subscription", "identifier" => "{\"channel\":\"ChatChannel\",\"room\":\"1\"}"}.to_json)
        socket.messages[1].should eq({identifier: "{\"channel\":\"ChatChannel\",\"room\":\"1\"}", message: {hello: "Broadcast!"}}.to_json)

        Cable::Logger.messages.size.should eq(3)
        Cable::Logger.messages[0].should eq("ChatChannel is streaming from chat_1")
        Cable::Logger.messages[1].should eq("ChatChannel is transmitting the subscription confirmation")
        Cable::Logger.messages[2].should eq("ChatChannel transmitting {\"hello\" => \"Broadcast!\"} (via streamed from chat_1)")
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
  request = HTTP::Request.new("GET", "#{Cable.settings.route}?test_token=98", headers)
end

private class DummySocket < HTTP::WebSocket
  getter messages : Array(String) = Array(String).new

  def send(message)
    @messages << message
  end
end

private class Organization
  getter name : String = "Acme Inc."

  def initialize
  end
end

private class User
  getter email : String

  def initialize(@email : String)
  end
end

private class ConnectionTest < Cable::Connection
  identified_by :identifier
  owned_by current_user : User
  owned_by organization : Organization

  def connect
    self.identifier = token
    self.current_user = User.new("user98@mail.com")
    self.organization = Organization.new
  end
end

private class UnauthorizedConnectionTest < Cable::Connection
  def connect
    reject_unauthorized_connection
  end
end

def connect(connection_class : Cable::Connection.class = ConnectionTest, &block)
  socket = DummySocket.new(IO::Memory.new)
  connection = connection_class.new(builds_request, socket)

  yield connection, socket

  connection.close
end
