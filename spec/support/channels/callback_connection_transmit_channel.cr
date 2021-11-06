class CallbackConnectionTransmitChannel < ApplicationCable::Channel
  after_subscribed :broadcast_welcome_pack

  def subscribed
    stream_from "callbacks_02"
  end

  # testing the type all at once to save time
  def broadcast_welcome_pack
    connection_transmit({"welcome" => "hash"})
    connection_transmit(%({"welcome": "json_string"}))
    connection_transmit(JSON.parse(%({"welcome": "json"})))
    connection_transmit("welcome_string")
  end
end
