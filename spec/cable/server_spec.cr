require "../spec_helper"
require "log/spec"

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

  describe "#shutdown" do
    it "closes the fiber_channel so the subscribed messages fiber doesn't leak" do
      Cable.reset_server
      Cable.temp_config(backend_class: Cable::DevBackend) do
        server = Cable.server
        server.fiber_channel.closed?.should be_false

        server.shutdown

        server.fiber_channel.closed?.should be_true
        # Sending to the closed channel must raise rather than silently leak.
        expect_raises(::Channel::ClosedError) do
          server.fiber_channel.send({"foo", "bar"})
        end
      end
      Cable.reset_server
    end
  end

  describe "remote disconnects" do
    it "disconnects all connections of an identifier but not one sharing its prefix" do
      Cable.reset_server
      Cable.temp_config(backend_class: Cable::DevBackend) do
        first_tab = creates_new_connection("1")
        second_tab = creates_new_connection("1")
        other_user = creates_new_connection("12")
        [first_tab, second_tab, other_user].each { |connection| Cable.server.add_connection(connection) }

        Cable.server.fiber_channel.send({"cable_internal/1", Cable.message(:disconnect)})
        wait_until { Cable.server.connections.size == 1 }

        Cable.server.connections.keys.should eq([other_user.connection_identifier])
        first_tab.closed?.should be_true
        second_tab.closed?.should be_true
        other_user.closed?.should be_false
        other_user.close
      end
    end

    it "disconnects a single connection by its full id" do
      Cable.reset_server
      Cable.temp_config(backend_class: Cable::DevBackend) do
        first_tab = creates_new_connection("1")
        second_tab = creates_new_connection("1")
        [first_tab, second_tab].each { |connection| Cable.server.add_connection(connection) }

        Cable.server.fiber_channel.send({"cable_internal/#{first_tab.connection_identifier}", Cable.message(:disconnect)})
        wait_until { Cable.server.connections.size == 1 }

        Cable.server.connections.keys.should eq([second_tab.connection_identifier])
        second_tab.close
      end
    end

    it "keeps the internal subscription while another connection of the identifier is open" do
      Cable.reset_server
      Cable.temp_config(backend_class: Cable::DevBackend) do
        Cable::DevBackend.reset
        first_tab = creates_new_connection("1")
        second_tab = creates_new_connection("1")
        [first_tab, second_tab].each do |connection|
          Cable.server.add_connection(connection)
          connection.subscribe(subscribe_payload("room_a"))
        end

        Cable.server.remove_connection(first_tab.connection_identifier)
        Cable::DevBackend.subscriptions.should contain("cable_internal/1")

        Cable.server.remove_connection(second_tab.connection_identifier)
        Cable::DevBackend.subscriptions.should_not contain("cable_internal/1")
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

  describe "#send_to_channels" do
    it "logs a single line per broadcast regardless of the number of subscribers" do
      Cable.reset_server
      Cable.temp_config(backend_class: Cable::DevBackend) do
        connection_1 = creates_new_connection("aa")
        connection_2 = creates_new_connection("bb")

        Cable.server.add_connection(connection_1)
        Cable.server.add_connection(connection_2)

        # Both connections stream from the same identifier ("chat_room_a")
        connection_1.subscribe(subscribe_payload("room_a"))
        connection_2.subscribe(subscribe_payload("room_a"))

        logs = Log.capture("cable") do
          Cable.server.send_to_channels("chat_room_a", {"message" => "hi"}.to_json)
        end

        logs.check(:info, /Transmitting .* to 2 subscribers \(via streamed from chat_room_a\)/)
        logs.empty

        connection_1.close
        connection_2.close
      end
      Cable.reset_server
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

def creates_new_connection(token : String?) : ApplicationCable::Connection
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

private def wait_until(&)
  100.times do
    return if yield
    sleep 10.milliseconds
  end
  raise "condition not met within 1s"
end
