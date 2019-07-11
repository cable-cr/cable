require "../spec_helper"

def builds_request
  headers = HTTP::Headers{
    "Upgrade"                => "websocket",
    "Connection"             => "Upgrade",
    "Sec-WebSocket-Key"      => "OqColdEJm3i9e/EqMxnxZw==",
    "Sec-WebSocket-Protocol" => "actioncable-v1-json, actioncable-unsupported",
    "Sec-WebSocket-Version"  => "13",
  }
  request = HTTP::Request.new("GET", "#{Cable.settings.route}?user_id=1", headers)
end

class DummySocket < HTTP::WebSocket
end

private class ConnectionTest < Cable::Connection
  def connect
    self.current_user = user_id
  end
end

describe Cable::Connection do
  it "matches the right route" do
    io = IO::Memory.new
    connection = ConnectionTest.new(builds_request, DummySocket.new(io))
  end
end
