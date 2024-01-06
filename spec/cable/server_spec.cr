require "../spec_helper"

include RequestHelpers

describe Cable::Server do
  describe "#remote_connections" do
    it "finds the connection and disconnects it" do
      Cable.reset_server
      Cable.temp_config(backend_class: Cable::DevBackend) do
        connection = creates_new_connection("abc123")
        Cable.server.add_connection(connection)
        connection.connection_identifier.should contain("abc123")

        Cable.server.remote_connections.find(connection.connection_identifier).disconnect
        Cable::DevBackend.published_messages.should contain({"cable_internal/#{connection.connection_identifier}", "disconnect"})
        connection.close
      end
    end
  end

  describe "#active_connections_for" do
    it "accurately returns active connections for a specificic token" do
      Cable.reset_server
      Cable.temp_config(backend_class: Cable::DevBackend) do
        Cable.server.active_connections_for("abc123").size.should eq(0)
        Cable.server.active_connections_for("def456").size.should eq(0)

        connection = creates_new_connection("abc123")
        Cable.server.add_connection(connection)

        Cable.server.active_connections_for("abc123").size.should eq(1)

        other_connection = creates_new_connection("def456")
        Cable.server.add_connection(other_connection)

        Cable.server.active_connections_for("def456").size.should eq(1)

        connection.close

        Cable.server.active_connections_for("abc123").size.should eq(0)
        Cable.server.active_connections_for("def456").size.should eq(1)

        other_connection.close

        Cable.server.active_connections_for("def456").size.should eq(0)
      end
    end
  end

  describe "#subscribed_channels_for" do
    it "accurately returns active channel subscriptions for a specificic token" do
      Cable.reset_server
      Cable.temp_config(backend_class: Cable::DevBackend) do
        connection_1 = creates_new_connection("aa")
        connection_2 = creates_new_connection("bb")

        Cable.server.add_connection(connection_1)
        Cable.server.add_connection(connection_2)

        Cable.server.subscribed_channels_for("aa").size.should eq(0)
        Cable.server.subscribed_channels_for("bb").size.should eq(0)

        connection_1.subscribe(subscribe_payload("room_a"))

        Cable.server.subscribed_channels_for("aa").size.should eq(1)
        Cable.server.subscribed_channels_for("bb").size.should eq(0)

        connection_1.subscribe(subscribe_payload("room_b"))

        Cable.server.subscribed_channels_for("aa").size.should eq(2)
        Cable.server.subscribed_channels_for("bb").size.should eq(0)

        connection_2.subscribe(subscribe_payload("room_a"))

        Cable.server.subscribed_channels_for("aa").size.should eq(2)
        Cable.server.subscribed_channels_for("bb").size.should eq(1)

        connection_1.close
        connection_2.close
      end
      Cable.reset_server
    end
  end
end

def creates_new_connection(token : String | Nil) : ApplicationCable::Connection
  ApplicationCable::Connection.new(builds_request(token: token), DummySocket.new(IO::Memory.new))
end

def subscribe_payload(room : String) : Cable::Payload
  payload_json = {
    command:    "subscribe",
    identifier: {
      channel: "ChatChannel",
      room:    room,
    }.to_json,
  }.to_json
  Cable::Payload.from_json(payload_json)
end
