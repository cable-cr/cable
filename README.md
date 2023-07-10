# Cable

[![ci workflow](https://github.com/cable-cr/cable/actions/workflows/ci.yml/badge.svg)](https://github.com/cable-cr/cable/actions/workflows/ci.yml)

It's like [ActionCable](https://guides.rubyonrails.org/action_cable_overview.html) (100% compatible with JS Client), but you know, for Crystal.

## Installation

1. Add the dependency to your `shard.yml`:

> NOTE: You must explicitly add the Redis shard also.

```yaml
dependencies:
  cable:
    github: cable-cr/cable
    branch: master # or use the latest version
  redis:
    github: jgaskins/redis
    branch: master # lock down if needed
```

> NOTE: You can only use a single Redis shard. We recommend https://github.com/jgaskins/redis. However, you can use the legacy shard https://github.com/stefanwille/crystal-redis.

2. Run `shards install`

## Usage

Application code
```crystal
require "cable"
require "cable/backend/redis/backend"
```

## Backend setup

At the moment, we only support a Redis backend.

### Redis

Due to some stability issues, we recently swapped the Redis shard.

To offer backwards compatibility, we still provide the ability to use the previous legacy shard. However, this may change in the future.

**Release 0.3**

Moving forward, from this release, we are officially supporting this [Redis shard](https://github.com/jgaskins/redis).

Prior to this release, we used this [Redis shard](https://github.com/stefanwille/crystal-redis).

However, since we cannot use two conflicting shards, we only run tests against our officially supported shard.

**Legacy Redis shard usage**

You can still choose to continue to use the legacy Redis shards.

```yaml
dependencies:
  cable:
    github: cable-cr/cable
  redis:
    github: stefanwille/crystal-redis
    version: ~> 2.8.0 # last tested version
```

Application code

```crystal
require "cable"
require "cable/backend/redis/legacy/backend"
```

**Testing the legacy Redis shard**

If you want to test the legacy shard locally, change these files;

```crystal
# spec/spec_helper.cr

# require "../src/backend/redis/backend"
require "../src/backend/redis/legacy/backend"
```

```yaml
# shard.yml

development_dependencies:
  # redis:
  #   github: jgaskins/redis
  #   version: ~> 0.5.0
  redis:
    github: stefanwille/crystal-redis
    version: ~> 2.8.0
```

Run `shards install`

## Lucky example

To help better illustrate how the entire setup looks, we'll use the [lucky web framework](https://luckyframework.org), but this will work in any Crystal web framework.

### Load the shard

```crystal
# src/shards.cr

require "cable"
require "cable/backend/redis/backend"
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
  settings.url = ENV.fetch("REDIS_URL", "redis://localhost:6379")

  # See Vanilla JS example below for more info
  settings.disable_sec_websocket_protocol_header = false

  # stability settings
  settings.redis_ping_interval = 15.seconds
  settings.restart_error_allowance = 20

  # DEPRECATED!
  # only use if you are using stefanwille/crystal-redis
  # AND you want to use the connection pool
  # Use a single publish connection by default.
  # settings.pool_redis_publish = false # set to `true` to enable a pooled connection on publish
  # settings.redis_pool_size = 5
  # settings.redis_pool_timeout = 5.0
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
      UserToken.decode_user_id(token.to_s).try do |user_id|
        self.identifier = user_id.to_s
        self.current_user =  UserQuery.find(user_id)
      end
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

## Redis

Redis is awesome, but it has complexities that need to be considered;

1. Redis Pub/Sub works really well until you lose the connection...
2. Redis connections can go stale without activity.
3. Redis connection TCP issues can cause unstable connections.
4. Redis DB's have a buffer related to the message sizes called [Output Buffer Limits](https://redis.io/docs/reference/clients/#output-buffer-limits). Exceeding this buffer will not disconnect the connection. It just yields it dead. You cannot know about this except by monitoring logs/metrics.

Here are some ways this shard can help with this.

### Restarting the server

When the first connection is made, the cable server spawns a single pub/sub connection for all subscriptions.
If the connection dies at any point, the server will continue to throw errors unless someone manually restarts the server...

The cable server provides an automated failure rate monitoring/restart function to automate the restart process.

When the server encounters (n) errors are trying to connect to the Redis connection, it restarts the server.
The error rate allowance avoids a vicious cycle i.e. (n) clients attempting to connect vs server restarts while Redis is down.
Generally, if the Redis connection is down, you'll exceed this error allowance quickly. So you may encounter severe back-to-back restarts if Redis is down for a substantial time.
This is expected for any system which uses a Redis backed, and Redis goes down. However, once Redis covers, Cable will self-heal and re-establish all the socket connections.

> NOTE: The automated restart process will also kill all the current client WS connections.
> However, this trade-off allows a fault-tolerant system vs leaving a dead Redis connection hanging around with no pub/sub activity.

**Restart allowance settings**

You can change this setting. However, we advise not going below 20.

```crystal
Cable.configure do |settings|
  settings.restart_error_allowance = 20 # default is 20. Use 0 to disable restarts
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

### Enable pooling and TCP keepalive

The Redis officially supported shard allows us to create a connection pool and also enable TCP keepalive settings.

**Recommended setup**

Start simple with the following settings.
The Redis shard has pretty good default settings for pooling and TCP keepalive.

```crystal
# .env

REDIS_URL: <redis_connection_string>?keepalive=true
```

```crystal
# config/cable.cr

Cable.configure do |settings|
  settings.url = ENV.fetch("REDIS_URL", "redis://localhost:6379")
end
```

> NOTE: This is not enabled by default. You must pass this param to the connection string to ensure this is enabled.

See the [full docs](https://github.com/jgaskins/redis#connection-pool) on the pooling and TCP keepalive capabilities.

### Increase your Redis [Output Buffer Limits](https://redis.io/docs/reference/clients/#output-buffer-limits)

> Technically, this shard cannot help with this.

Exceeding this buffer should be avoided to ensure a stable pub/sub connection.

Options;

1. Double or triple this setting on your Redis DB. 32Mb is usually the default.
2. Ensure you truncate the message sizes client side.

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

## TODO

After reading the docs, I realized I'm using some weird naming for variables/methods, so

- [x] Need to make a connection use an identifier
- [x] Add `identified_by identifier` to `Cable::Connection`
- [x] Give better methods to reject a connection
- [x] Refactor, Connection class, is so bloated
- [ ] Allow tracing and observability hooks.
- [ ] Allow external bug tracking hooks.
- [ ] Allow custom JSON formatted logs.
- [ ] Clean up of naming to make it easier for others to contribute.
- [ ] Add an async/local adapter (make tests, development, and small deploys simpler)
- [ ] Add PostgreSQL backend

## First Class Citizen

- [ ] Better integrate with Lucky, maybe with generators or something else?
- [ ] Add support for Kemal
- [ ] Add support for Amber

The idea is to create different modules, `Cable::Lucky`, `Cable::Kemal`, `Cable::Amber`, and make them easy to use with any crystal web framework.

## Contributing

You know, fork-branch-push-pr 😉 don't be shy. Participate as you want!
