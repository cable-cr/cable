module RequestHelpers
  def builds_request(token : String) : HTTP::Request
    headers = HTTP::Headers{
      "Upgrade"                => "websocket",
      "Connection"             => "Upgrade",
      "Sec-WebSocket-Key"      => "OqColdEJm3i9e/EqMxnxZw==",
      "Sec-WebSocket-Protocol" => "actioncable-v1-json, actioncable-unsupported",
      "Sec-WebSocket-Version"  => "13",
    }
    HTTP::Request.new("GET", "#{Cable.settings.route}?test_token=#{token}", headers)
  end

  def builds_request(token : Nil) : HTTP::Request
    headers = HTTP::Headers{
      "Upgrade"                => "websocket",
      "Connection"             => "Upgrade",
      "Sec-WebSocket-Key"      => "OqColdEJm3i9e/EqMxnxZw==",
      "Sec-WebSocket-Protocol" => "actioncable-v1-json, actioncable-unsupported",
      "Sec-WebSocket-Version"  => "13",
    }
    HTTP::Request.new("GET", Cable.settings.route, headers)
  end
end
