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

    it "keeps closing the remaining connections when one raises on close" do
      Cable.reset_server
      Cable.temp_config(backend_class: Cable::DevBackend) do
        server = Cable.server
        exploding = ExplodingConnection.new(builds_request(token: "boom"), DummySocket.new(IO::Memory.new))
        healthy = creates_new_connection("fine")
        server.add_connection(exploding)
        server.add_connection(healthy)

        server.shutdown

        healthy.closed?.should be_true
        server.fiber_channel.closed?.should be_true
        FakeExceptionService.exceptions.any? do |report|
          report.exception.message == "socket exploded" &&
            report.message.includes?("Cable::Server#shutdown(connection.close)") &&
            report.connection == exploding
        end.should be_true
      end
      Cable.reset_server
    end

    it "lets Cable.restart swap in a new server when a connection raises on close" do
      Cable.reset_server
      Cable.temp_config(backend_class: Cable::DevBackend) do
        old_server = Cable.server
        exploding = ExplodingConnection.new(builds_request(token: "boom"), DummySocket.new(IO::Memory.new))
        old_server.add_connection(exploding)

        Cable.restart

        Cable.server.should_not eq(old_server)
        old_server.fiber_channel.closed?.should be_true
        FakeExceptionService.size.should eq(1)
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

    it "keeps delivering to the rest of the stream when one socket is dead" do
      Cable.reset_server
      Cable.temp_config(backend_class: Cable::DevBackend) do
        dead = creates_new_connection("dead", BrokenSocket.new(IO::Memory.new))
        live = creates_new_connection("live")

        # Registration order is delivery order, so the dead socket goes first
        streams_from(ChatChannel.new(dead, dead.identifier, no_params), "probe")
        streams_from(ChatChannel.new(live, live.identifier, no_params), "probe")

        Cable.server.send_to_channels("probe", {"hello" => "world"}.to_json)

        live.socket.as(DummySocket).messages.size.should eq(1)
        FakeExceptionService.size.should eq(1)
        FakeExceptionService.exceptions.first.connection.should eq(dead)
        live.close
      end
      Cable.reset_server
    end

    it "delivers to every channel on the stream" do
      Cable.reset_server
      Cable.temp_config(backend_class: Cable::DevBackend) do
        first = creates_new_connection("first")
        second = creates_new_connection("second")

        streams_from(ChatChannel.new(first, first.identifier, no_params), "probe")
        streams_from(ChatChannel.new(second, second.identifier, no_params), "probe")

        Cable.server.send_to_channels("probe", {"hello" => "world"}.to_json)

        first.socket.as(DummySocket).messages.size.should eq(1)
        second.socket.as(DummySocket).messages.size.should eq(1)
        first.close
        second.close
      end
      Cable.reset_server
    end

    it "evicts a channel whose socket failed, so later broadcasts skip it" do
      Cable.reset_server
      Cable.temp_config(backend_class: Cable::DevBackend) do
        broken_socket = BrokenSocket.new(IO::Memory.new)
        dead = creates_new_connection("dead", broken_socket)
        live = creates_new_connection("live")

        streams_from(ChatChannel.new(dead, dead.identifier, no_params), "probe")
        streams_from(ChatChannel.new(live, live.identifier, no_params), "probe")

        3.times { Cable.server.send_to_channels("probe", {"hello" => "world"}.to_json) }

        broken_socket.attempts.should eq(1)
        live.socket.as(DummySocket).messages.size.should eq(3)
        live.close
      end
      Cable.reset_server
    end

    it "evicts a closed connection without dropping the channels after it" do
      Cable.reset_server
      Cable.temp_config(backend_class: Cable::DevBackend) do
        closed = creates_new_connection("closed")
        live = creates_new_connection("live")

        streams_from(ChatChannel.new(closed, closed.identifier, no_params), "probe")
        streams_from(ChatChannel.new(live, live.identifier, no_params), "probe")
        closed.socket.close

        2.times { Cable.server.send_to_channels("probe", {"hello" => "world"}.to_json) }

        closed.socket.as(DummySocket).messages.should be_empty
        live.socket.as(DummySocket).messages.size.should eq(2)
        live.close
      end
      Cable.reset_server
    end

    it "runs an evicted channel's unsubscribed once and contains its failure" do
      Cable.reset_server
      Cable.temp_config(backend_class: Cable::DevBackend) do
        LeavingChannel.unsubscribed_calls = 0
        dead = creates_new_connection("dead", BrokenSocket.new(IO::Memory.new))
        live = creates_new_connection("live")

        streams_from(LeavingChannel.new(dead, dead.identifier, no_params), "probe")
        streams_from(ChatChannel.new(live, live.identifier, no_params), "probe")

        2.times { Cable.server.send_to_channels("probe", {"hello" => "world"}.to_json) }
        wait_until { LeavingChannel.unsubscribed_calls > 0 }

        LeavingChannel.unsubscribed_calls.should eq(1)
        live.socket.as(DummySocket).messages.size.should eq(2)
        live.close
      end
      Cable.reset_server
    end
    it "skips a channel whose deliver? returns false and still delivers to the rest" do
      Cable.reset_server
      Cable.temp_config(backend_class: Cable::DevBackend) do
        filtered = creates_new_connection("filtered")
        live = creates_new_connection("live")

        streams_from(FilteringChannel.new(filtered, filtered.identifier, no_params), "probe")
        streams_from(ChatChannel.new(live, live.identifier, no_params), "probe")

        Cable.server.send_to_channels("probe", {"secret" => true}.to_json)

        filtered.socket.as(DummySocket).messages.should be_empty
        live.socket.as(DummySocket).messages.size.should eq(1)
        filtered.close
        live.close
      end
      Cable.reset_server
    end

    it "delivers to a filtering channel when deliver? returns true for the message" do
      Cable.reset_server
      Cable.temp_config(backend_class: Cable::DevBackend) do
        filtered = creates_new_connection("filtered")

        streams_from(FilteringChannel.new(filtered, filtered.identifier, no_params), "probe")

        Cable.server.send_to_channels("probe", {"secret" => true}.to_json)
        Cable.server.send_to_channels("probe", {"hello" => "world"}.to_json)

        filtered.socket.as(DummySocket).messages.size.should eq(1)
        filtered.socket.as(DummySocket).messages.first.should contain("world")
        filtered.close
      end
      Cable.reset_server
    end

    it "only counts channels that were actually delivered to in the broadcast log" do
      Cable.reset_server
      Cable.temp_config(backend_class: Cable::DevBackend) do
        filtered = creates_new_connection("filtered")
        live = creates_new_connection("live")

        streams_from(FilteringChannel.new(filtered, filtered.identifier, no_params), "probe")
        streams_from(ChatChannel.new(live, live.identifier, no_params), "probe")

        logs = Log.capture("cable") do
          Cable.server.send_to_channels("probe", {"secret" => true}.to_json)
        end

        logs.check(:info, /Transmitting .* to 1 subscriber \(via streamed from probe\)/)
        logs.empty
        filtered.close
        live.close
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

class ExplodingConnection < ApplicationCable::Connection
  def close
    raise "socket exploded"
  end
end

# Fails the way a client that went away fails
class BrokenSocket < DummySocket
  getter attempts = 0

  def send(message)
    @attempts += 1
    raise IO::Error.new("Broken pipe")
  end
end

# Raises from the app-level teardown hook, the way a channel whose
# `unsubscribed` touches a database can
class LeavingChannel < ApplicationCable::Channel
  class_property unsubscribed_calls = 0

  def unsubscribed
    LeavingChannel.unsubscribed_calls += 1
    raise "simulated teardown failure"
  end
end

# Drops any message flagged as secret, the way an app channel filters
# what reaches a particular subscriber
class FilteringChannel < ApplicationCable::Channel
  def deliver?(message) : Bool
    !(message.is_a?(JSON::Any) && message["secret"]?.try(&.as_bool?))
  end
end

def creates_new_connection(token : String?, socket : HTTP::WebSocket = DummySocket.new(IO::Memory.new)) : ApplicationCable::Connection
  ApplicationCable::Connection.new(builds_request(token: token), socket)
end

def streams_from(channel : Cable::Channel, stream : String)
  Cable.server.subscribe_channel(channel: channel, identifier: stream)
end

def no_params : Hash(String, Cable::Payload::RESULT)
  {} of String => Cable::Payload::RESULT
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
