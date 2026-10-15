require "../spec_helper"

describe Cable::Expectations do
  describe "broadcast_to" do
    it "passes when a message was broadcast to the stream" do
      with_dev_backend do
        ChatChannel.broadcast_to("rooms:1", "hello")

        Cable::DevBackend.published_messages.should broadcast_to("rooms:1")
      end
    end

    it "fails when nothing was broadcast to the stream" do
      with_dev_backend do
        ChatChannel.broadcast_to("rooms:1", "hello")

        expectation = broadcast_to("rooms:2")
        expectation.match(Cable::DevBackend.published_messages).should be_false
      end
    end

    it "passes should_not when nothing was broadcast to the stream" do
      with_dev_backend do
        ChatChannel.broadcast_to("rooms:1", "hello")

        Cable::DevBackend.published_messages.should_not broadcast_to("events:4")
      end
    end

    it "matches a string payload exactly" do
      with_dev_backend do
        ChatChannel.broadcast_to("rooms:1", "hello")

        Cable::DevBackend.published_messages.should broadcast_to("rooms:1", "hello")
        Cable::DevBackend.published_messages.should_not broadcast_to("rooms:1", "goodbye")
      end
    end

    it "matches a hash payload regardless of key order" do
      with_dev_backend do
        ChatChannel.broadcast_to("rooms:1", {"a" => "1", "b" => "2"})

        Cable::DevBackend.published_messages.should broadcast_to("rooms:1", {"b" => "2", "a" => "1"})
        Cable::DevBackend.published_messages.should_not broadcast_to("rooms:1", {"a" => "1"})
      end
    end

    it "matches a JSON::Any payload against a hash broadcast" do
      with_dev_backend do
        ChatChannel.broadcast_to("rooms:1", {"a" => "1"})

        Cable::DevBackend.published_messages.should broadcast_to("rooms:1", JSON.parse(%({"a": "1"})))
      end
    end

    it "does not match a non-JSON string against a hash payload" do
      with_dev_backend do
        ChatChannel.broadcast_to("rooms:1", "not json")

        Cable::DevBackend.published_messages.should_not broadcast_to("rooms:1", {"a" => "1"})
      end
    end

    it "describes the actual broadcasts in the failure message" do
      with_dev_backend do
        ChatChannel.broadcast_to("rooms:1", "hello")

        message = broadcast_to("rooms:2", "yo").failure_message(Cable::DevBackend.published_messages)
        message.should contain(%(Expected a broadcast to "rooms:2" with payload "yo"))
        message.should contain(%("rooms:1" => "hello"))
      end
    end

    it "explains when nothing at all was published" do
      with_dev_backend do
        message = broadcast_to("rooms:2").failure_message(Cable::DevBackend.published_messages)
        message.should contain(%(Expected a broadcast to "rooms:2"))
        message.should contain("no messages were published")
        message.should contain("Cable::DevBackend")
      end
    end

    it "describes the unexpected broadcast in the negative failure message" do
      with_dev_backend do
        ChatChannel.broadcast_to("rooms:1", "hello")

        message = broadcast_to("rooms:1").negative_failure_message(Cable::DevBackend.published_messages)
        message.should contain(%(Expected no broadcast to "rooms:1"))
        message.should contain(%("rooms:1" => "hello"))
      end
    end
  end
end

private def with_dev_backend(&)
  Cable.reset_server
  Cable.temp_config(backend_class: Cable::DevBackend) do
    yield
  end
end
