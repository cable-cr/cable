class RejectionChannel < ApplicationCable::Channel
  def subscribed
    # We don't support stream_for, needs to generate your own unique string
    stream_from "rejection"
    reject # we are rejecting any connection here
  end

  def receive(message)
    broadcast_message = {} of String => String
    if message.is_a?(String)
      broadcast_message["message"] = message
    else
      broadcast_message["message"] = message["message"].to_s
    end
    broadcast_message["current_user"] = connection.identifier
    RejectionChannel.broadcast_to("rejection", broadcast_message)
  end

  def unsubscribed
    # You can do any action after channel is unsubscribed
  end
end
