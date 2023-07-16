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
end
