require "../spec_helper"

include RequestHelpers

describe Cable::Server do
  describe "#remote_connections" do
    it "finds the connection and disconnects it" do
      Cable.reset_server
      Cable.temp_config(backend_class: Cable::DevBackend) do
        connect do |connection, _socket|
          Cable.server.remote_connections.find(connection.connection_identifier).disconnect
          Cable::DevBackend.published_messages.should contain({"cable_internal/#{connection.connection_identifier}", "disconnect"})
        end
      end
    end
  end
end
