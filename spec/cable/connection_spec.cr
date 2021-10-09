require "../spec_helper"

describe Cable::Connection do
  it "matches the right route" do
    connect do |connection, socket|
    end
  end

  describe "#subscribe" do
    it "accepts" do
      connect do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
        sleep 0.1

        socket.messages.should contain({"type" => "confirm_subscription", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)

        connection.close
        socket.close
        Cable::Logger.messages.should contain("ChatChannel is streaming from chat_1")
        Cable::Logger.messages.should contain("ChatChannel is transmitting the subscription confirmation")
        Cable::Logger.messages.should contain("ChatChannel stopped streaming from {\"channel\":\"ChatChannel\",\"room\":\"1\"}")
      end
    end

    it "accepts without params hash key" do
      connect do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
        sleep 0.1

        socket.messages.should contain({"type" => "confirm_subscription", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)

        connection.close
        socket.close
        Cable::Logger.messages.should contain("ChatChannel is streaming from chat_1")
        Cable::Logger.messages.should contain("ChatChannel is transmitting the subscription confirmation")
        Cable::Logger.messages.should contain("ChatChannel stopped streaming from {\"channel\":\"ChatChannel\",\"room\":\"1\"}")
      end
    end

    it "accepts with nested hash" do
      connect do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1", person: {name: "Foo", age: 32, boom: "boom"}}.to_json}.to_json)
        sleep 0.1

        socket.messages.should contain({"type" => "confirm_subscription", "identifier" => {channel: "ChatChannel", room: "1", person: {name: "Foo", age: 32, boom: "boom"}}.to_json}.to_json)

        connection.close
        socket.close
        Cable::Logger.messages.should contain("ChatChannel is streaming from chat_1")
        Cable::Logger.messages.should contain("ChatChannel is transmitting the subscription confirmation")
        Cable::Logger.messages.should contain("ChatChannel stopped streaming from {\"channel\":\"ChatChannel\",\"room\":\"1\",\"person\":{\"name\":\"Foo\",\"age\":32,\"boom\":\"boom\"}}")
      end
    end

    it "accepts without auth token" do
      connect(connection_class: ConnectionNoTokenTest, token: nil) do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1", person: {name: "Celso", age: 32, boom: "boom"}}.to_json}.to_json)
        sleep 0.1

        socket.messages.should contain({"type" => "confirm_subscription", "identifier" => {channel: "ChatChannel", room: "1", person: {name: "Celso", age: 32, boom: "boom"}}.to_json}.to_json)

        connection.close
        socket.close
        Cable::Logger.messages.should contain("ChatChannel is streaming from chat_1")
        Cable::Logger.messages.should contain("ChatChannel is transmitting the subscription confirmation")
        Cable::Logger.messages.should contain("ChatChannel stopped streaming from {\"channel\":\"ChatChannel\",\"room\":\"1\",\"person\":{\"name\":\"Celso\",\"age\":32,\"boom\":\"boom\"}}")
      end
    end
  end

  describe "#unsubscribe" do
    it "unsubscribes from a channel" do
      connect do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
        connection.receive({"command" => "unsubscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
        sleep 0.1

        socket.messages.should contain({"type" => "confirm_subscription", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
        socket.messages.should contain({"type" => "confirm_unsubscription", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)

        connection.close
        socket.close
        Cable::Logger.messages.should contain("ChatChannel is streaming from chat_1")
        Cable::Logger.messages.should contain("ChatChannel is transmitting the subscription confirmation")
        Cable::Logger.messages.should contain("ChatChannel stopped streaming from {\"channel\":\"ChatChannel\",\"room\":\"1\"}")
        Cable::Logger.messages.should contain("ChatChannel is transmitting the unsubscribe confirmation")
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
    it "rejects the unauthorized connection (and does not receive any message)" do
      connect(UnauthorizedConnectionTest) do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
        connection.receive({"command" => "message", "identifier" => {channel: "ChatChannel", room: "1"}.to_json, "data" => {message: "Hello"}.to_json}.to_json)

        socket.messages.size.should eq(0)

        # we check only the first that is the one we care about, the others make no sense to our test
        Cable::Logger.messages.should contain("An unauthorized connection attempt was rejected")
        socket.closed?.should be_truthy
      end
    end
  end

  describe "#message" do
    it "ignore a message for a non valid channel" do
      connect do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
        connection.receive({"command" => "message", "identifier" => {channel: "UnknownChannel", room: "1"}.to_json, "data" => {invite_id: "3", action: "invite"}.to_json}.to_json)
        sleep 0.1

        socket.messages.should contain({"type" => "confirm_subscription", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)

        connection.close
        socket.close
        Cable::Logger.messages.should contain("ChatChannel is streaming from chat_1")
        Cable::Logger.messages.should contain("ChatChannel is transmitting the subscription confirmation")
        Cable::Logger.messages.should contain("ChatChannel stopped streaming from {\"channel\":\"ChatChannel\",\"room\":\"1\"}")
      end
    end

    it "receives a message and send to Channel#receive" do
      connect do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
        sleep 0.1
        connection.receive({"command" => "message", "identifier" => {channel: "ChatChannel", room: "1"}.to_json, "data" => {message: "Hello"}.to_json}.to_json)
        sleep 0.1

        socket.messages.should contain({"type" => "confirm_subscription", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
        socket.messages.should contain({"identifier" => {channel: "ChatChannel", room: "1"}.to_json, "message" => {message: "Hello", current_user: "98"}}.to_json)

        connection.close
        socket.close
        Cable::Logger.messages.should contain("ChatChannel is streaming from chat_1")
        Cable::Logger.messages.should contain("ChatChannel is transmitting the subscription confirmation")
        Cable::Logger.messages.should contain("ChatChannel#receive({\"message\" => \"Hello\"})")
        Cable::Logger.messages.should contain("[ActionCable] Broadcasting to chat_1: {\"message\" => \"Hello\", \"current_user\" => \"98\"}")
        Cable::Logger.messages.should contain("ChatChannel transmitting {\"message\" => \"Hello\", \"current_user\" => \"98\"} (via streamed from chat_1)")
        Cable::Logger.messages.should contain("ChatChannel stopped streaming from {\"channel\":\"ChatChannel\",\"room\":\"1\"}")
      end
    end

    it "receives a message with an action key and sends to Channel#Perform" do
      connect do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
        sleep 0.1
        connection.receive({"command" => "message", "identifier" => {channel: "ChatChannel", room: "1"}.to_json, "data" => {invite_id: "4", action: "invite"}.to_json}.to_json)
        sleep 0.1

        socket.messages.should contain({"type" => "confirm_subscription", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
        socket.messages.should contain({"identifier" => {channel: "ChatChannel", room: "1"}.to_json, "message" => {"performed" => "invite", "params" => "4"}}.to_json)

        connection.close
        socket.close
        Cable::Logger.messages.should contain("ChatChannel is streaming from chat_1")
        Cable::Logger.messages.should contain("ChatChannel is transmitting the subscription confirmation")
        Cable::Logger.messages.should contain("ChatChannel#perform(\"invite\", {\"invite_id\" => \"4\"})")
        Cable::Logger.messages.should contain("[ActionCable] Broadcasting to chat_1: {\"performed\" => \"invite\", \"params\" => \"4\"}")
        Cable::Logger.messages.should contain("ChatChannel transmitting {\"performed\" => \"invite\", \"params\" => \"4\"} (via streamed from chat_1)")
        Cable::Logger.messages.should contain("ChatChannel stopped streaming from {\"channel\":\"ChatChannel\",\"room\":\"1\"}")
      end
    end
  end

  describe "#broadcast_to" do
    it "sends the broadcasted message" do
      connect do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
        sleep 0.1
        connection.broadcast_to(ConnectionTest::CHANNELS[connection.connection_identifier][{channel: "ChatChannel", room: "1"}.to_json], {hello: "Broadcast!"}.to_json)

        socket.messages.should contain({"type" => "confirm_subscription", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)

        connection.close
        socket.close
        Cable::Logger.messages.should contain("ChatChannel is streaming from chat_1")
        Cable::Logger.messages.should contain("ChatChannel is transmitting the subscription confirmation")
        Cable::Logger.messages.should contain("ChatChannel stopped streaming from {\"channel\":\"ChatChannel\",\"room\":\"1\"}")
      end
    end
  end

  describe ".broadcast_to" do
    it "sends the broadcasted message" do
      connect do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
        sleep 0.1
        ConnectionTest.broadcast_to("chat_1", {hello: "Broadcast!"}.to_json)
        sleep 0.1

        socket.messages.should contain({"type" => "confirm_subscription", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
        socket.messages.should contain({identifier: {channel: "ChatChannel", room: "1"}.to_json, message: {hello: "Broadcast!"}}.to_json)

        connection.close
        socket.close
        Cable::Logger.messages.should contain("ChatChannel is streaming from chat_1")
        Cable::Logger.messages.should contain("ChatChannel is transmitting the subscription confirmation")
        Cable::Logger.messages.should contain("ChatChannel transmitting {\"hello\" => \"Broadcast!\"} (via streamed from chat_1)")
        Cable::Logger.messages.should contain("ChatChannel stopped streaming from {\"channel\":\"ChatChannel\",\"room\":\"1\"}")
      end
    end
  end

  describe "when channel broadcast a message" do
    describe "as string" do
      it "receives correctly" do
        connect do |connection, socket|
          connection.receive({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
          sleep 0.1
          ChatChannel.broadcast_to(channel: "chat_1", message: "<turbo-stream></turbo-stream>")
          sleep 0.1

          socket.messages.should contain({"type" => "confirm_subscription", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
          socket.messages.should contain({"identifier" => {channel: "ChatChannel", room: "1"}.to_json, "message" => "<turbo-stream></turbo-stream>"}.to_json)

          connection.close
          socket.close
          Cable::Logger.messages.should contain("ChatChannel is streaming from chat_1")
          Cable::Logger.messages.should contain("ChatChannel is transmitting the subscription confirmation")
          Cable::Logger.messages.should contain("[ActionCable] Broadcasting to chat_1: <turbo-stream></turbo-stream>")
          Cable::Logger.messages.should contain("ChatChannel transmitting <turbo-stream></turbo-stream> (via streamed from chat_1)")
          Cable::Logger.messages.should contain("ChatChannel stopped streaming from {\"channel\":\"ChatChannel\",\"room\":\"1\"}")
        end
      end
    end

    describe "as Hash(String, String)" do
      it "receives correctly" do
        connect do |connection, socket|
          connection.receive({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
          sleep 0.1
          ChatChannel.broadcast_to(channel: "chat_1", message: {"foo" => "bar"})
          sleep 0.1

          socket.messages.should contain({"type" => "confirm_subscription", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
          socket.messages.should contain({"identifier" => {channel: "ChatChannel", room: "1"}.to_json, "message" => {"foo" => "bar"}}.to_json)

          connection.close
          socket.close
          Cable::Logger.messages.should contain("ChatChannel is streaming from chat_1")
          Cable::Logger.messages.should contain("ChatChannel is transmitting the subscription confirmation")
          Cable::Logger.messages.should contain("[ActionCable] Broadcasting to chat_1: {\"foo\" => \"bar\"}")
          Cable::Logger.messages.should contain("ChatChannel transmitting {\"foo\" => \"bar\"} (via streamed from chat_1)")
          Cable::Logger.messages.should contain("ChatChannel stopped streaming from {\"channel\":\"ChatChannel\",\"room\":\"1\"}")
        end
      end
    end

    describe "as JSON::Any" do
      it "receives correctly" do
        connect do |connection, socket|
          connection.receive({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
          sleep 0.1
          json_message = JSON.parse(%({"foo": "bar"}))
          ChatChannel.broadcast_to(channel: "chat_1", message: json_message)
          sleep 0.1

          socket.messages.should contain({"type" => "confirm_subscription", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
          socket.messages.should contain({"identifier" => {channel: "ChatChannel", room: "1"}.to_json, "message" => {"foo" => "bar"}}.to_json)

          connection.close
          socket.close
          Cable::Logger.messages.should contain("ChatChannel is streaming from chat_1")
          Cable::Logger.messages.should contain("ChatChannel is transmitting the subscription confirmation")
          Cable::Logger.messages.should contain("[ActionCable] Broadcasting to chat_1: {\"foo\" => \"bar\"}")
          Cable::Logger.messages.should contain("ChatChannel transmitting {\"foo\" => \"bar\"} (via streamed from chat_1)")
          Cable::Logger.messages.should contain("ChatChannel stopped streaming from {\"channel\":\"ChatChannel\",\"room\":\"1\"}")
        end
      end
    end
  end

  describe "when channel rejects a connection" do
    it "does not send any message to that connection related to the channel" do
      connect do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
        connection.receive({"command" => "subscribe", "identifier" => {channel: "RejectionChannel"}.to_json}.to_json)
        sleep 0.1
        json_message = JSON.parse(%({"foo": "bar"}))
        ChatChannel.broadcast_to(channel: "chat_1", message: json_message)

        json_message = JSON.parse(%({"foo": "bar"}))
        RejectionChannel.broadcast_to(channel: "rejection", message: json_message)
        sleep 0.1

        # Even after broadcasting to Rejection channel, we can check the socket didn't receive it
        socket.messages.should contain({"type" => "confirm_subscription", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
        socket.messages.should contain({"type" => "reject_subscription", "identifier" => {channel: "RejectionChannel"}.to_json}.to_json)
        socket.messages.should contain({"identifier" => {channel: "ChatChannel", room: "1"}.to_json, "message" => {"foo" => "bar"}}.to_json)

        connection.close
        socket.close
        Cable::Logger.messages.should contain("ChatChannel is streaming from chat_1")
        Cable::Logger.messages.should contain("ChatChannel is transmitting the subscription confirmation")
        Cable::Logger.messages.should contain("RejectionChannel is transmitting the subscription rejection")
        Cable::Logger.messages.should contain("[ActionCable] Broadcasting to chat_1: {\"foo\" => \"bar\"}")
        # and here we can confirm the message was broadcasted
        Cable::Logger.messages.should contain("ChatChannel transmitting {\"foo\" => \"bar\"} (via streamed from chat_1)")
        Cable::Logger.messages.should contain("[ActionCable] Broadcasting to rejection: {\"foo\" => \"bar\"}")
        Cable::Logger.messages.should contain("ChatChannel stopped streaming from {\"channel\":\"ChatChannel\",\"room\":\"1\"}")
      end
    end
  end
end

def builds_request(token : String)
  headers = HTTP::Headers{
    "Upgrade"                => "websocket",
    "Connection"             => "Upgrade",
    "Sec-WebSocket-Key"      => "OqColdEJm3i9e/EqMxnxZw==",
    "Sec-WebSocket-Protocol" => "actioncable-v1-json, actioncable-unsupported",
    "Sec-WebSocket-Version"  => "13",
  }
  request = HTTP::Request.new("GET", "#{Cable.settings.route}?test_token=#{token}", headers)
end

def builds_request(token : Nil)
  headers = HTTP::Headers{
    "Upgrade"                => "websocket",
    "Connection"             => "Upgrade",
    "Sec-WebSocket-Key"      => "OqColdEJm3i9e/EqMxnxZw==",
    "Sec-WebSocket-Protocol" => "actioncable-v1-json, actioncable-unsupported",
    "Sec-WebSocket-Version"  => "13",
  }
  request = HTTP::Request.new("GET", "#{Cable.settings.route}", headers)
end

private class DummySocket < HTTP::WebSocket
  getter messages : Array(String) = Array(String).new

  def send(message)
    return if closed?
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
    if tk = token
      self.identifier = tk
    end
    self.current_user = User.new("user98@mail.com")
    self.organization = Organization.new
  end

  def broadcast_to(channel, message)
  end
end

private class ConnectionNoTokenTest < Cable::Connection
  identified_by :uuid

  def connect
    self.uuid = UUID.random.to_s
  end

  def broadcast_to(channel, message)
  end
end

private class UnauthorizedConnectionTest < Cable::Connection
  def connect
    reject_unauthorized_connection
  end
end

def connect(connection_class : Cable::Connection.class = ConnectionTest, token : String? = "98", &block)
  socket = DummySocket.new(IO::Memory.new)
  connection = connection_class.new(builds_request(token: token), socket)

  yield connection, socket

  connection.close
end
