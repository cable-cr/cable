# Cable

[![ci workflow](https://github.com/cable-cr/cable/actions/workflows/ci.yml/badge.svg)](https://github.com/cable-cr/cable/actions/workflows/ci.yml)

It's like [ActionCable](https://guides.rubyonrails.org/action_cable_overview.html) (100% compatible with JS Client), but you know, for Crystal.

## Installation

1. Add the dependency to your `shard.yml`:

```yaml
dependencies:
  cable:
    github: cable-cr/cable
    branch: master # or use the latest version
  # Specify which backend you want to use
  cable-redis:
    github: cable-cr/cable-redis
    branch: main
```

Cable supports multiple backends. The most common one is Redis, but there's a few to choose from with more being added:

Since there are multiple different versions of Redis for Crystal, you can choose which one you want to use.
* [jgaskins/redis](https://github.com/cable-cr/cable-redis)
* [stefanwille/crystal-redis](https://github.com/cable-cr/cable-redis-legacy)

Or if you don't want to use Redis, you can try one of these alternatives

* [NATS](https://github.com/cable-cr/cable-nats)

2. Run `shards install`

## Usage

Application code
```crystal
require "cable"
# Or whichever backend you chose
require "cable-redis"
```

## Lucky example

To help better illustrate how the entire setup looks, we'll use [Lucky](https://luckyframework.org), but this will work in any Crystal web framework.

### Load the shard

```crystal
# src/shards.cr

require "cable"
require "cable-redis"
```

### Mount the middleware

Add the `Cable::Handler` before `Lucky::RouteHandler`

```crystal
# src/app_server.cr

class AppServer < Lucky::BaseAppServer
  def middleware
    [
      Cable::Handler(ApplicationCable::Connection).new, # place before the middleware below
      Honeybadger::Handler.new,
      Lucky::ErrorHandler.new(action: Errors::Show),
      Lucky::RouteHandler.new,
    ]
   end
end
```

### Configure cable settings

After that, you can configure your `Cable server`. The defaults are:

```crystal
# config/cable.cr

Cable.configure do |settings|
  settings.route = "/cable"    # the URL your JS Client will connect
  settings.token = "token"     # The query string parameter used to get the token
  settings.url = ENV.fetch("CABLE_BACKEND_URL", "redis://localhost:6379")
  settings.backend_class = Cable::RedisBackend
  settings.backend_ping_interval = 15.seconds
  settings.restart_error_allowance = 20
  settings.on_error = ->(error : Exception, message : String) do
    # or whichever error reportings you're using
    Bugsnag.report(error) do |event|
      event.app.app_type = "lucky"
      event.meta_data = {
        "error_class" => JSON::Any.new(error.class.name),
        "message"     => JSON::Any.new(message),
      }
    end
  end
end
```

### Configure logging level

You may want to tune how to report logging.

```crystal
# config/log.cr

log_levels = {
  "debug" => Log::Severity::Debug,
  "info"  => Log::Severity::Info,
  "error" => Log::Severity::Error,
}

# use the `CABLE_DEBUG_LEVEL` env var to choose any of the 3 log levels above
Cable::Logger.level = log_levels[ENV.fetch("CABLE_DEBUG_LEVEL", "info")]
```

Alternatively, use a global log level which matches you application log code also.

See [Crystal API docs](https://crystal-lang.org/api/1.6.1/Log.html#configure-logging-from-environment-variables) for more details..

```crystal
# config/log.cr

# use the `LOG_LEVEL` env var

Cable::Logger.setup_from_env(default_level: :warn)
```

> NOTE: The volume of logs produced are high... If log costs are a concern, use `warn` level to only receive critical logs

### Setup the main application connection and channel classes

Then you need to implement a few classes.

The connection class is how you are going to handle connections. It's referenced in the `src/app_server.cr` file when creating the handler.

```crystal
# src/channels/application_cable/connection.cr

module ApplicationCable
  class Connection < Cable::Connection
    # You need to specify how you identify the class, using something like:
    # Remembering that it must be a String
    # Tip: Use your `User#id` converted to String
    identified_by :identifier

    # If you'd like to keep a `User` instance together with the Connection, so
    # there's no need to fetch from the database all the time, you can use the
    # `owned_by` instruction
    owned_by current_user : User


    def connect
      user_id : Int64? = UserToken.decode_user_id(token.to_s)

      # We were unable to authenticate the user, we should raise an
      # unauthorized exception
      if !user_id
          raise UnathorizedConnectionException.new
      end

      self.identifier = user_id.to_s
      self.current_user =  UserQuery.find(user_id)
    end
  end
end
```

Then you need you a base channel to make it easy to inherit your app's Cable logic.

```crystal
# src/channels/application_cable/channel.cr

module ApplicationCable
  class Channel < Cable::Channel
    # some potential shared logic or helpers
  end
end
```

### Create your app channels

**Kitchen sink example**

Then create your cables, as much as your want!! Let's set up a `ChatChannel` as an example:

```crystal
# src/channels/chat_channel.cr

class ChatChannel < ApplicationCable::Channel
  def subscribed
    # We don't support stream_for, needs to generate your own unique string
    stream_from "chat_#{params["room"]}"
  end

  def receive(data)
    broadcast_message = {} of String => String
    broadcast_message["message"] = data["message"].to_s
    broadcast_message["current_user_id"] = connection.identifier
    ChatChannel.broadcast_to("chat_#{params["room"]}", broadcast_message)
  end

  def perform(action, action_params)
    user = UserQuery.new.find(connection.identifier)
    # Perform actions on a user object. For example, you could manage
    # its status by adding some .away and .status methods on it like below
    # user.away if action == "away"
    # user.status(action_params["status"]) if action == "status"
    ChatChannel.broadcast_to("chat_#{params["room"]}", {
      "user"      => user.email,
      "performed" => action.to_s,
    })
  end

  def unsubscribed
    #  Perform any action after the client closes the connection.
    user = UserQuery.new.find(connection.identifier)

    # You could, for example, call any method on your user
    # user.logout
  end
end
```

**Rejection example**

Reject channel subscription if the request is invalid:

```crystal
# src/channels/chat_channel.cr

class ChatChannel < ApplicationCable::Channel
  def subscribed
    reject if user_not_allowed_to_join_chat_room?

    stream_from "chat_#{params["room"]}"
  end
end
```

**Callbacks example**

Use callbacks to perform actions or transmit messages once the connection/channel has been subscribed.

```crystal
# src/channels/chat_channel.cr

class ChatChannel < ApplicationCable::Channel
  # you can name these callbacks anything you want...
  # `after_subscribed` can accept 1 or more callbacks to be run in order
  after_subscribed :broadcast_welcome_pack_to_single_subscribed_user,
                   :announce_user_joining_to_everyone_else_in_the_channel,
                   :process_some_stuff

  def subscribed
    stream_from "chat_#{params["room"]}"
  end

  # If you ONLY need to send the current_user a message
  # and none of the other subscribers
  #
  # use -> transmit(message), which accepts Hash(String, String) or String
  def broadcast_welcome_pack_to_single_subscribed_user
    transmit({ "welcome_pack" => "some cool stuff for this single user" })
  end

  # On the other hand,
  # if you want to broadcast a message
  # to all subscribers connected to this channel
  #
  # use -> broadcast(message), which accepts Hash(String, String) or String
  def announce_user_joining_to_everyone_else_in_the_channel
    broadcast("username xyz just joined")
  end

  # you don't need to use the transmit functionality
  def process_some_stuff
    send_welcome_email_to_user
    update_their_profile
  end
end
```

## Error handling

You can setup a hook to report errors to any 3rd party service you choose.

```crystal
# config/cable.cr
Cable.configure do |settings|
  settings.on_error = ->(exception : Exception, message : String) do
    # new 3rd part service handler
    ExceptionService.notify(exception, message: message)
    # default logic
    Cable::Logger.error(exception: exception) { message }
  end
end
```
**Default Handler**

```crystal
Habitat.create do
  setting on_error : Proc(Exception, String, Nil) = ->(exception : Exception, message : String) do
    Cable::Logger.error(exception: exception) { message }
  end
end
```

> NOTE: The message field will contain details regarding which class/method raised the error

## Client-Side

Check below on the JavaScript section how to communicate with the Cable backend.

### JavaScript

It works with [ActionCable](https://www.npmjs.com/package/actioncable) JS Client out-of-the-box!! Yeah, that's really cool no? If you need to adapt, make a hack, or something like that?!

No, you don't need it! Just read the few lines below and start playing with Cable in 5 minutes!

### ActionCable JS Example

[examples/action-cable-js-client.md](examples/action-cable-js-client.md)

### Vanilla JS Examples

If you want to use this shard with iOS clients or vanilla JS using react etc., there is an example in the [examples](examples/) folder.

> Note - If you are using a vanilla - non-action-cable JS client, you may want to disable the action cable response headers as they cause issues for clients who don't know how to handle them. Set a Habitat disable_sec_websocket_protocol_header like so to disable those headers;

```crystal
# config/cable.cr

Cable.configure do |settings|
  settings.disable_sec_websocket_protocol_header = true
end
```

## Debugging

You can create a JSON endpoint to ping the server and check how things are going.

```crystal
# src/actions/debug/index.cr

class Debug::Index < ApiAction
  include RequireAuthToken

  get "/debug" do
    json(Cable.server.debug_json) # Cable.server.debug_json is provided by this shard
  end
end
```

Alternatively, you can ping Redis directly using the redis-cli as follows;

```bash
PUBLISH _internal debug
```

This will dump a debug status into the logs.

## Contributing

1. Fork it (<https://github.com/cable-cr/cable/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
