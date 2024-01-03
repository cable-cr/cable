require "../spec_helper"

include RequestHelpers

describe Cable::Connection do
  describe "#close" do
    it "closes the connection socket even without channel subscriptions" do
      connect do |connection, _socket|
        connection.closed?.should eq(false)
        connection.close
        connection.closed?.should eq(true)
      end
    end
    it "removes the connection channel on close" do
      connect do |connection, _socket|
        connection.receive({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
        ConnectionTest::CHANNELS.keys.size.should eq(1)
        connection.close
        ConnectionTest::CHANNELS.keys.size.should eq(0)
      end
    end
  end

  describe "#receive" do
    it "ignores empty messages" do
      connect do |connection, socket|
        connection.receive("")
        sleep 0.1

        socket.messages.size.should eq(0)

        connection.close
        socket.close
      end
    end

    it "ignores incorrect json structures" do
      connect do |connection, socket|
        # The handler handles exception catching
        # so we just make sure the correct exception is thrown
        expect_raises(JSON::SerializableError) do
          connection.receive([{command: "subscribe"}].to_json)
        end

        sleep 0.1

        socket.messages.size.should eq(0)

        connection.close
        socket.close
      end
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
      end
    end

    it "accepts without params hash key" do
      connect do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => {channel: "AppearanceChannel"}.to_json}.to_json)
        sleep 0.1

        socket.messages.should contain({"type" => "confirm_subscription", "identifier" => {channel: "AppearanceChannel"}.to_json}.to_json)

        connection.close
        socket.close
      end
    end

    it "accepts with nested hash" do
      connect do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1", person: {name: "Foo", age: 32, boom: "boom"}}.to_json}.to_json)
        sleep 0.1

        socket.messages.should contain({"type" => "confirm_subscription", "identifier" => {channel: "ChatChannel", room: "1", person: {name: "Foo", age: 32, boom: "boom"}}.to_json}.to_json)

        connection.close
        socket.close
      end
    end

    it "accepts without auth token" do
      connect(connection_class: ConnectionNoTokenTest, token: nil) do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1", person: {name: "Celso", age: 32, boom: "boom"}}.to_json}.to_json)
        sleep 0.1

        socket.messages.should contain({"type" => "confirm_subscription", "identifier" => {channel: "ChatChannel", room: "1", person: {name: "Celso", age: 32, boom: "boom"}}.to_json}.to_json)

        connection.close
        socket.close
      end
    end

    it "blocks the same connection from subscribing to the same channel multiple times" do
      connect do |connection, socket|
        connection.receive({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
        sleep 0.1
        connection.receive({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
        sleep 0.1
        connection.receive({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)

        # ensure we only allow subscribing to the same channel once from a connection
        socket.messages.size.should eq(1)
        socket.messages.should contain({"type" => "confirm_subscription", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)

        connection.close
        socket.close
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
      end
    end
  end

  describe ".identified_by" do
    it "uses the right identifier name for it" do
      connect do |connection, _socket|
        connection.identifier.should eq("98")
      end

      connect(connection_class: ConnectionWithDifferentIndentifierTest) do |connection, _socket|
        connection.identifier.should eq("98")
      end
    end
  end

  describe ".owned_by" do
    it "uses the right identifier name for it" do
      connect do |connection, _socket|
        connection.current_user.as(User).email.should eq("user98@mail.com")
        connection.organization.as(Organization).name.should eq("Acme Inc.")
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
        socket.closed?.should be_truthy

        Cable.server.connections.should eq({} of String => Cable::Connection)
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
        end
      end

      it "receives string json correctly" do
        connect do |connection, socket|
          connection.receive({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
          sleep 0.1
          json_message = %({"foo": "bar"})
          ChatChannel.broadcast_to(channel: "chat_1", message: json_message)
          sleep 0.1

          socket.messages.should contain({"type" => "confirm_subscription", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
          socket.messages.should contain({"identifier" => {channel: "ChatChannel", room: "1"}.to_json, "message" => JSON.parse(%({"foo": "bar"}))}.to_json)

          connection.close
          socket.close
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
        end
      end
    end
  end

  describe "when Cable.server.publish broadcasts a message" do
    describe "as string" do
      it "receives correctly" do
        connect do |connection, socket|
          connection.receive({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
          sleep 0.1
          Cable.server.publish(channel: "chat_1", message: "<turbo-stream></turbo-stream>")
          sleep 0.1

          socket.messages.should contain({"type" => "confirm_subscription", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
          socket.messages.should contain({"identifier" => {channel: "ChatChannel", room: "1"}.to_json, "message" => "<turbo-stream></turbo-stream>"}.to_json)

          connection.close
          socket.close
        end
      end

      it "receives string json correctly" do
        connect do |connection, socket|
          connection.receive({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
          sleep 0.1
          json_message = %({"foo": "bar"})
          Cable.server.publish(channel: "chat_1", message: json_message)
          sleep 0.1

          socket.messages.should contain({"type" => "confirm_subscription", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
          socket.messages.should contain({"identifier" => {channel: "ChatChannel", room: "1"}.to_json, "message" => JSON.parse(%({"foo": "bar"}))}.to_json)

          connection.close
          socket.close
        end
      end
    end

    describe "as JSON::Any (string)" do
      it "receives correctly" do
        connect do |connection, socket|
          connection.receive({"command" => "subscribe", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
          sleep 0.1
          Cable.server.publish(channel: "chat_1", message: %({"foo": "bar"}))
          sleep 0.1

          socket.messages.should contain({"type" => "confirm_subscription", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
          socket.messages.should contain({"identifier" => {channel: "ChatChannel", room: "1"}.to_json, "message" => {"foo" => "bar"}}.to_json)

          connection.close
          socket.close
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
        socket.messages.size.should eq(3)
        socket.messages.should contain({"type" => "confirm_subscription", "identifier" => {channel: "ChatChannel", room: "1"}.to_json}.to_json)
        socket.messages.should contain({"type" => "reject_subscription", "identifier" => {channel: "RejectionChannel"}.to_json}.to_json)
        socket.messages.should contain({"identifier" => {channel: "ChatChannel", room: "1"}.to_json, "message" => {"foo" => "bar"}}.to_json)
        socket.messages.should_not contain({"identifier" => {channel: "RejectionChannel"}.to_json, "message" => {"foo" => "bar"}}.to_json)

        connection.close
        socket.close
        # and here we can confirm the message was broadcasted
      end
    end
  end

  describe ".after_subscribed callbacks with #transmit" do
    it "receives all broadcast messages" do
      socket_1 = DummySocket.new(IO::Memory.new)
      socket_2 = DummySocket.new(IO::Memory.new)

      connection_1 = ConnectionTest.new(builds_request(token: "98"), socket_1)
      connection_2 = ConnectionTest.new(builds_request(token: "101"), socket_2)

      connection_1.receive({"command" => "subscribe", "identifier" => {channel: "CallbackTransmitChannel"}.to_json}.to_json)
      sleep 0.1
      CallbackTransmitChannel.broadcast_to(channel: "callbacks_01", message: "<turbo-stream></turbo-stream>")
      sleep 0.1

      connection_2.receive({"command" => "subscribe", "identifier" => {channel: "CallbackTransmitChannel"}.to_json}.to_json)
      sleep 0.1
      CallbackTransmitChannel.broadcast_to(channel: "callbacks_01", message: "<turbo-stream>2nd</turbo-stream>")
      sleep 0.1

      # since socket_1 was connected first
      # 1 x received the subscribe command message
      # 1 x received the first broadcast_to -> <turbo-stream></turbo-stream>
      # 4 x callback#transmit messages
      #
      # Then when socket_2 got connected
      # 1 x it received the 2nd broadcast_to -> <turbo-stream>2nd</turbo-stream>
      # 4 x it received the 2nd batch of callback#transmit messages
      socket_1.messages.size.should eq(1 + 1 + 4 + 1 + 4)
      socket_1.messages.should contain({"type" => "confirm_subscription", "identifier" => {channel: "CallbackTransmitChannel"}.to_json}.to_json)
      socket_1.messages.should contain({"identifier" => {channel: "CallbackTransmitChannel"}.to_json, "message" => "<turbo-stream></turbo-stream>"}.to_json)
      socket_1.messages.should contain({"identifier" => {channel: "CallbackTransmitChannel"}.to_json, "message" => "<turbo-stream>2nd</turbo-stream>"}.to_json)

      # transmit messages
      socket_1.messages.should contain({"identifier" => {channel: "CallbackTransmitChannel"}.to_json, "message" => {"welcome" => "hash"}}.to_json)
      socket_1.messages.should contain({"identifier" => {channel: "CallbackTransmitChannel"}.to_json, "message" => {"welcome" => "json_string"}}.to_json)
      socket_1.messages.should contain({"identifier" => {channel: "CallbackTransmitChannel"}.to_json, "message" => {"welcome" => "json"}}.to_json)
      socket_1.messages.should contain({"identifier" => {channel: "CallbackTransmitChannel"}.to_json, "message" => "welcome_string"}.to_json)

      # since socket_2 was connected after socket_1
      # 1 x received the subscribe command message
      # 1 x received the 2nd broadcast_to -> <turbo-stream>2nd</turbo-stream>
      # 4 x callback#transmit messages
      socket_2.messages.size.should eq(1 + 1 + 4)
      socket_2.messages.should contain({"type" => "confirm_subscription", "identifier" => {channel: "CallbackTransmitChannel"}.to_json}.to_json)
      socket_2.messages.should contain({"identifier" => {channel: "CallbackTransmitChannel"}.to_json, "message" => "<turbo-stream>2nd</turbo-stream>"}.to_json)

      # transmit messages
      socket_2.messages.should contain({"identifier" => {channel: "CallbackTransmitChannel"}.to_json, "message" => {"welcome" => "hash"}}.to_json)
      socket_2.messages.should contain({"identifier" => {channel: "CallbackTransmitChannel"}.to_json, "message" => {"welcome" => "json_string"}}.to_json)
      socket_2.messages.should contain({"identifier" => {channel: "CallbackTransmitChannel"}.to_json, "message" => {"welcome" => "json"}}.to_json)
      socket_2.messages.should contain({"identifier" => {channel: "CallbackTransmitChannel"}.to_json, "message" => "welcome_string"}.to_json)

      connection_1.close
      connection_2.close
      socket_1.close
      socket_2.close
    end
  end

  describe ".after_subscribed callbacks with #connection_transmit" do
    it "receives all broadcast messages" do
      socket_1 = DummySocket.new(IO::Memory.new)
      socket_2 = DummySocket.new(IO::Memory.new)

      connection_1 = ConnectionTest.new(builds_request(token: "98"), socket_1)
      connection_2 = ConnectionTest.new(builds_request(token: "101"), socket_2)

      connection_1.receive({"command" => "subscribe", "identifier" => {channel: "CallbackConnectionTransmitChannel"}.to_json}.to_json)
      sleep 0.1
      CallbackConnectionTransmitChannel.broadcast_to(channel: "callbacks_02", message: "<turbo-stream></turbo-stream>")
      sleep 0.1

      connection_2.receive({"command" => "subscribe", "identifier" => {channel: "CallbackConnectionTransmitChannel"}.to_json}.to_json)
      sleep 0.1
      CallbackConnectionTransmitChannel.broadcast_to(channel: "callbacks_02", message: "<turbo-stream>2nd</turbo-stream>")
      sleep 0.1

      # since socket_1 was connected first
      # 1 x received the subscribe command message
      # 1 x received the first broadcast_to -> <turbo-stream></turbo-stream>
      # 4 x callback#transmit messages
      #
      # It will not receive any of the messages sent to socket_2
      socket_1.messages.size.should eq(1 + 1 + 4 + 1)
      socket_1.messages.should contain({"type" => "confirm_subscription", "identifier" => {channel: "CallbackConnectionTransmitChannel"}.to_json}.to_json)
      socket_1.messages.should contain({"identifier" => {channel: "CallbackConnectionTransmitChannel"}.to_json, "message" => "<turbo-stream></turbo-stream>"}.to_json)
      socket_1.messages.should contain({"identifier" => {channel: "CallbackConnectionTransmitChannel"}.to_json, "message" => "<turbo-stream>2nd</turbo-stream>"}.to_json)

      # transmit messages
      socket_1.messages.should contain({"identifier" => {channel: "CallbackConnectionTransmitChannel"}.to_json, "message" => {"welcome" => "hash"}}.to_json)
      socket_1.messages.should contain({"identifier" => {channel: "CallbackConnectionTransmitChannel"}.to_json, "message" => {"welcome" => "json_string"}}.to_json)
      socket_1.messages.should contain({"identifier" => {channel: "CallbackConnectionTransmitChannel"}.to_json, "message" => {"welcome" => "json"}}.to_json)
      socket_1.messages.should contain({"identifier" => {channel: "CallbackConnectionTransmitChannel"}.to_json, "message" => "welcome_string"}.to_json)

      # since socket_2 was connected after socket_1
      # 1 x received the subscribe command message
      # 1 x received the 2nd broadcast_to -> <turbo-stream>2nd</turbo-stream>
      # 4 x callback#transmit messages
      socket_2.messages.size.should eq(1 + 1 + 4)
      socket_2.messages.should contain({"type" => "confirm_subscription", "identifier" => {channel: "CallbackConnectionTransmitChannel"}.to_json}.to_json)
      socket_2.messages.should contain({"identifier" => {channel: "CallbackConnectionTransmitChannel"}.to_json, "message" => "<turbo-stream>2nd</turbo-stream>"}.to_json)

      # transmit messages
      socket_2.messages.should contain({"identifier" => {channel: "CallbackConnectionTransmitChannel"}.to_json, "message" => {"welcome" => "hash"}}.to_json)
      socket_2.messages.should contain({"identifier" => {channel: "CallbackConnectionTransmitChannel"}.to_json, "message" => {"welcome" => "json_string"}}.to_json)
      socket_2.messages.should contain({"identifier" => {channel: "CallbackConnectionTransmitChannel"}.to_json, "message" => {"welcome" => "json"}}.to_json)
      socket_2.messages.should contain({"identifier" => {channel: "CallbackConnectionTransmitChannel"}.to_json, "message" => "welcome_string"}.to_json)

      connection_1.close
      connection_2.close
      socket_1.close
      socket_2.close
    end
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

private class ConnectionWithDifferentIndentifierTest < Cable::Connection
  identified_by :identifier_test
  owned_by current_user : User
  owned_by organization : Organization

  def connect
    if tk = token
      self.identifier_test = tk
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

def connect(connection_class : Cable::Connection.class = ConnectionTest, token : String? = "98", &)
  socket = DummySocket.new(IO::Memory.new)
  connection = connection_class.new(builds_request(token: token), socket)

  yield connection, socket

  connection.close
end
