class ChatChannel < ApplicationCable::Channel
  def subscribed
    # We don't support stream_for, needs to generate your own unique string
    stream_from "chat_#{params["room"]}"
  end

  def receive(message)
    broadcast_message = {} of String => String
    if message.is_a?(String)
      broadcast_message["message"] = message
    else
      broadcast_message["message"] = message["message"].to_s
    end
    broadcast_message["current_user"] = connection.identifier
    ChatChannel.broadcast_to("chat_#{params["room"]}", broadcast_message)
  end

  def perform(action, action_params)
    ChatChannel.broadcast_to("chat_#{params["room"]}", {
      "performed" => action.to_s,
      "params"    => action_params["invite_id"].to_s,
    })
  end

  def unsubscribed
    # You can do any action after channel is unsubscribed
  end
end
