class DummySocket < HTTP::WebSocket
  getter messages : Array(String) = Array(String).new

  def send(message)
    return if closed?
    @messages << message
  end
end
