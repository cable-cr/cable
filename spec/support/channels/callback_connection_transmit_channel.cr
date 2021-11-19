class CallbackConnectionTransmitChannel < ApplicationCable::Channel
  after_subscribed :broadcast_welcome_pack

  def subscribed
    stream_from "callbacks_02"
  end

  # testing the type all at once to save time
  def broadcast_welcome_pack
    transmit({"welcome" => "hash"})
    transmit(%({"welcome": "json_string"}))
    transmit(JSON.parse(%({"welcome": "json"})))
    transmit("welcome_string")
  end
end
