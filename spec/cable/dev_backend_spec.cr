require "../spec_helper"

include RequestHelpers

describe Cable::DevBackend do
  it "stores the broadcast" do
    # This is required because the RedisBackend is
    # configured by default and memoized
    Cable.reset_server
    Cable.temp_config(backend_class: Cable::DevBackend) do
      ChatChannel.broadcast_to("chat_party", "Yo yo!")

      Cable::DevBackend.published_messages.should contain({"chat_party", "Yo yo!"})
    end
  end
end
