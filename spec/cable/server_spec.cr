require "../spec_helper"

include RequestHelpers

describe Cable::Server do
  describe "#remote_connections" do
    it "finds the connection and disconnects it" do
      Cable.reset_server
      Cable.temp_config(backend_class: Cable::DevBackend) do
        socket = DummySocket.new(IO::Memory.new)
        request = builds_request("abc123")
        connection = ApplicationCable::Connection.new(request, socket)
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

        socket = DummySocket.new(IO::Memory.new)
        request = builds_request("abc123")
        connection = ApplicationCable::Connection.new(request, socket)
        Cable.server.add_connection(connection)

        Cable.server.active_connections_for("abc123").size.should eq(1)

        other_socket = DummySocket.new(IO::Memory.new)
        other_request = builds_request("def456")
        other_connection = ApplicationCable::Connection.new(other_request, other_socket)
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
end
