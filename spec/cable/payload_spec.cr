require "../spec_helper"

describe Cable::Payload do
  it "parses a single hash" do
    payload_json = {
      command:    "subscribe",
      identifier: {
        channel: "ChatChannel",
        person:  {name: "Foo", age: 32, boom: "boom"},
        foo:     "bar",
      }.to_json,
    }.to_json

    payload = Cable::Payload.from_json(payload_json)
    payload.command.should eq("subscribe")
    payload.identifier.key.should eq({channel: "ChatChannel", person: {name: "Foo", age: 32, boom: "boom"}, foo: "bar"}.to_json)
    payload.channel.should eq("ChatChannel")
    payload.channel_params.should eq({"person" => {"name" => "Foo", "age" => 32, "boom" => "boom"}, "foo" => "bar"})
  end

  it "parses a perform command" do
    payload_json = {
      command:    "message",
      identifier: {
        channel: "ChatChannel",
      }.to_json,
      data: {invite_id: 3, action: "invite"}.to_json,
    }.to_json

    payload = Cable::Payload.from_json(payload_json)
    payload.command.should eq("message")
    payload.identifier.key.should eq({channel: "ChatChannel"}.to_json)
    payload.channel.should eq("ChatChannel")
    payload.data.should eq({"invite_id" => 3})
    payload.action?.should be_truthy
    payload.action.should eq("invite")
  end

  it "raises a SerializableError when the identifier is not a string" do
    payload_json = {
      command:    "subscribe",
      identifier: {
        channel: "ChatChannel",
        person:  {name: "Foo", age: 32, boom: "boom"},
        foo:     "bar",
      },
    }.to_json

    expect_raises(JSON::SerializableError) do
      Cable::Payload.from_json(payload_json)
    end
  end
end
