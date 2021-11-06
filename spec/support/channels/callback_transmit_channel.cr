class CallbackTransmitChannel < ApplicationCable::Channel
  after_subscribed :announce_user_joining_1, :announce_user_joining_2

  def subscribed
    stream_from "callbacks_01"
  end

  # testing the type all at once to save time
  def announce_user_joining_1
    transmit({"welcome" => "hash"})
    transmit(%({"welcome": "json_string"}))
  end

  def announce_user_joining_2
    transmit(JSON.parse(%({"welcome": "json"})))
    transmit("welcome_string")
  end
end
