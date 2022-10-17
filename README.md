# Cable

[![ci workflow](https://github.com/cable-cr/cable/actions/workflows/ci.yml/badge.svg)](https://github.com/cable-cr/cable/actions/workflows/ci.yml)

It's like [ActionCable](https://guides.rubyonrails.org/action_cable_overview.html) (100% compatible with JS Client), but you know, for Crystal

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     cable:
       github: cable-cr/cable
   ```

2. Run `shards install`

## Usage

```crystal
require "cable"
```

### Lucky example

On your `src/app_server.cr` add the `Cable::Handler` before `Lucky::RouteHandler`

```crystal
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

After that, you can configure your `Cable`, the defaults are:

```crystal
Cable.configure do |settings|
  settings.route = "/cable"    # the URL your JS Client will connect
  settings.token = "token"     # The query string parameter used to get the token
  settings.url = ENV.fetch("REDIS_URL", "redis://localhost:6379")

  # See Vanilla JS example below for more info
  settings.disable_sec_websocket_protocol_header = false

  # Use a single publish connection by default.
  settings.pool_redis_publish = false # set to `true` to enable a pooled connection on publish
  settings.redis_pool_size = 5
  settings.redis_pool_timeout = 5.0
  settings.redis_ping_interval = 15.seconds
  settings.restart_error_allowance = 20
end
```

You may want to tune how to report logging

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

Then you need to implement a few classes

The connection class is how you are gonna handle connections, it's referenced on the `src/app_server.cr` when creating the handler.

```crystal
module ApplicationCable
  class Connection < Cable::Connection
    # You need to specify how you identify the class, using something like:
    # Remembering that it must, be a String
    # Tip: Use your `User#id` converted to String
    identified_by :identifier

    # If you'd like to keep a `User` instance together with the Connection, so
    # there's no need to fetch from the database all the time, you can use the
    # `owned_by` instruction
    owned_by current_user : User

    def connect
      UserToken.decode_user_id(token.to_s).try do |user_id|
        self.identifier = user_id.to_s
        self.current_user =  UserQuery.find(user_id)
      end
    end
  end
end
```

Then you need your base channel, just to make easy to aggregate your app's cables logic

```crystal
module ApplicationCable
  class Channel < Cable::Channel
  end
end
```

Then create your cables, as much as your want!! Let's setup a `ChatChannel` as example:

```crystal
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
    # Perform action on your user object. For example, you could manage
    # its status by adding some .away and .status methods on it like below
    # user.away if action == "away"
    # user.status(action_params["status"]) if action == "status"
    ChatChannel.broadcast_to("chat_#{params["room"]}", {
      "user"      => user.email,
      "performed" => action.to_s,
    })
  end

  def unsubscribed
    # You can do any action after client closes connection
    user = UserQuery.new.find(connection.identifier)

    # You could for example call any method on your user like a .logout one
    # user.logout
  end
end
```

Reject channel subscription if the request is invalid:

```crystal
class ChatChannel < ApplicationCable::Channel
  def subscribed
    reject if user_not_allowed_to_join_chat_room?

    stream_from "chat_#{params["room"]}"
  end
end
```

Use callbacks to perform actions or transmit messages once the connection/channel has been subscribed.

```crystal
class ChatChannel < ApplicationCable::Channel
  # you can name these callbacks anything you want...
  # `after_subscribed` can accept 1 or more callbacks to be run in order
  after_subscribed :broadcast_welcome_pack_to_single_subscribed_user,
                   :announce_user_joining_to_everyone_else_in_the_channel,
                   :process_some_stuff

  def subscribed
    stream_from "chat_#{params["room"]}"
  end

  # If you want to ONLY send the current_user a message
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

  # you don't need to use transmit functionality
  def process_some_stuff
    send_welcome_email_to_user
    update_their_profile
  end
end
```

## Redis

Redis has complexities that need to be considered;

1. Redis Pub/Sub works really well until you lose the connection...
2. Redis connections can go stale without activity.
3. Redis DB's have a buffer related to the message sizes called [Output Buffer Limits](https://redis.io/docs/reference/clients/#output-buffer-limits). Exceeding this buffer will not disconnect the connection. It just yields it dead. You cannot know about this except by monitoring logs/metrics.

Here are some ways this shard can help with this.

### Restarting the server

When the first connection is made, the cable server spawns a single pub/sub connection for all subscriptions.
If the connection dies at any point, the server will continue to throw errors unless someone manually restarts the server...

The cable server provides an automated failure rate monitoring/restart function to automate the restart process.

When the server encounters (n) errors are trying to connect to the Redis connection, it restarts the server.
The error rate allowance avoids a vicious cycle > of clients attempting to connect vs server restarts while Redis is down.
Generally, if the Redis connection is down, you'll exceed this error allowance quickly. So you may encounter severe back-to-back restarts if Redis is down for a substantial time.

> NOTE: The automated restart process will also kill all the current client WS connections.
> However, this trade-off allows a fault-tolerant system vs leaving a dead Redis connection hanging around with no pub/sub activity.

You can change this setting. However, we advise not going below 20.

```crystal
Cable.configure do |settings|
 settings.restart_error_allowance = 20 # default is 20.
 settings.restart_error_allowance = 0 # Use 0 to disable this
end
```

> NOTE: An error log `Cable.restart` will be invoked whenever a restart happens. We highly advise you to monitor these logs.

### Maintain Redis connection activity

When the first connection is made, the cable server starts a Redis PING/PONG task, which runs every 15 seconds. This helps to keep the Redis connection from going stale.

You can change this setting. However, we advise not going over 60 seconds.

```crystal
Cable.configure do |settings|
 settings.redis_ping_interval = 15.seconds # default is 15.
end
```

### Increase your Redis [Output Buffer Limits](https://redis.io/docs/reference/clients/#output-buffer-limits)

> Technically, this shard cannot help with this.

Exceeding this buffer should be avoided to ensure a stable pub/sub connection.

Options;

1. Double or triple this setting on your Redis DB. 32Mb is usually the default.
2. Ensure you truncate the message sizes client side.

Check below on the JavaScript section how to communicate with the Cable backend

## JavaScript

It works with [ActionCable](https://www.npmjs.com/package/actioncable) JS Client out-of-the-box!! Yeah, that's really cool no? If you need to adapt, make a hack, or something like that?!

No, you don't need! Just read the few lines below and start playing with Cable in 5 minutes!

### ActionCable JS Example

`/examples/action-cable-js-client.md`

### Vanilla JS Examples

If you want to use this shard with an iOS clients or vanilla JS using react etc. there is an example in the `/examples` folder.

> Note - If your using a vanilla - non action-cable JS client, you may want to disable the action cable response headers as they cause issues on the clients who don't know how to handle them. Set an Habitat disable_sec_websocket_protocol_header like so to disable those headers;

```crystal
# config/cable.cr

Cable.configure do |settings|
  settings.disable_sec_websocket_protocol_header = true
end
```

## Debugging

You can create a json endpoint to ping your server and check how things are going.

```crystal

# src/actions/debug/index.cr

class Debug::Index < ApiAction
  include RequireAuthToken

  get "/debug" do
    json(Cable.server.debug_json) # Cable.server.debug_json is provided by this shard
  end
end
```

Alternatively, you can ping redis directly using the redis-cli as follows;

```bash
PUBLISH _internal debug
```

This will dump a debug status into your logs

## TODO

After reading the docs, I realized I'm using some weird naming for variables / methods, so

- [x] Need to make connection use identifier
- [x] Add `identified_by identifier` to `Cable::Connection`
- [x] Give better methods to reject a connection
- [x] Refactor, Connection class is soooo bloated
- [ ] Add an async/local adapter (make tests, development and small deploys simpler)

## First Class Citizen

- [ ] Better integrate with Lucky, maybe with generators, or something else?
- [ ] Add support for Kemal
- [ ] Add support for Amber

Idea is create different modules, `Cable::Lucky`, `Cable::Kemal`, `Cable::Amber`, and make it easy to use with any crystal web framework

## Contributing

You know, fork-branch-push-pr 😉 don't be shy, participate as you want!
