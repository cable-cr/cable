class AppearanceChannel < ApplicationCable::Channel
  def subscribed
    # We don't support stream_for, needs to generate your own unique string
    stream_from "appearance_channel"
    AppearanceChannel.broadcast_to("appearance_channel", {"action" => "online", "user" => connection.current_user})
  end

  def unsubscribed
    AppearanceChannel.broadcast_to("appearance_channel", {"action" => "offline", "user" => connection.current_user})
  end

  def receive(message)
    # puts "Appearance Received: #{message}"
  end
end
