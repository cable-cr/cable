module Cable
  module Expectations
    alias Payload = String | JSON::Any | Hash(String, String)

    def broadcast_to(stream_identifier : String, message : Payload? = nil) : BroadcastToExpectation
      BroadcastToExpectation.new(stream_identifier, message)
    end

    struct BroadcastToExpectation
      def initialize(@stream_identifier : String, @message : Payload?)
      end

      def match(published_messages : Array(Tuple(String, String))) : Bool
        published_messages.any? do |stream_identifier, message|
          stream_identifier == @stream_identifier && payload_matches?(message)
        end
      end

      def failure_message(published_messages : Array(Tuple(String, String))) : String
        String.build do |io|
          io << "Expected a broadcast to " << @stream_identifier.inspect
          describe_expected_payload(io)
          if published_messages.empty?
            io << ", but no messages were published. "
            io << "Make sure Cable::DevBackend is the configured backend_class."
          else
            io << ", but got broadcasts to:\n"
            describe_broadcasts(io, published_messages)
          end
        end
      end

      def negative_failure_message(published_messages : Array(Tuple(String, String))) : String
        String.build do |io|
          io << "Expected no broadcast to " << @stream_identifier.inspect
          describe_expected_payload(io)
          io << ", but got broadcasts to:\n"
          describe_broadcasts(io, published_messages)
        end
      end

      private def payload_matches?(actual : String) : Bool
        case expected = @message
        in Nil
          true
        in String
          expected == actual
        in JSON::Any, Hash(String, String)
          JSON.parse(actual) == JSON.parse(expected.to_json)
        end
      rescue JSON::ParseException
        false
      end

      private def describe_expected_payload(io : IO) : Nil
        if expected = @message
          io << " with payload " << expected.inspect
        end
      end

      private def describe_broadcasts(io : IO, published_messages : Array(Tuple(String, String))) : Nil
        published_messages.join(io, '\n') do |(stream_identifier, message), inner|
          inner << "  " << stream_identifier.inspect << " => " << message.inspect
        end
      end
    end
  end
end
