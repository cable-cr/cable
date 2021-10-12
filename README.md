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
      Cable::Handler.new(ApplicationCable::Connection),
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
end
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

Check below on the JavaScript section how to communicate with the Cable backend

## JavaScript

It works with [ActionCable](https://www.npmjs.com/package/actioncable) JS Client out-of-the-box!! Yeah, that's really cool no? If you need to adapt, make a hack, or something like that?! No, you don't need! Just read the few lines below and start playing with Cable in 5 minutes!

If you are using Rails, then you already has a `app/assets/javascripts/cable.js` file that requires `action_cable`, you just need to connect to the right URL (don't forgot the settings you used), to authenticate using JWT use something like:

```js
(function() {
  this.App || (this.App = {});

  App.cable = ActionCable.createConsumer(
    "ws://localhost:5000/cable?token=JWT_TOKEN" // if using the default options
  );
}.call(this));
```

then on your `app/assets/javascripts/channels/chat.js`

```js
App.channels || (App.channels = {});

App.channels["chat"] = App.cable.subscriptions.create(
  {
    channel: "ChatChannel",
    room: "1"
  },
  {
    connected: function() {
      return console.log("ChatChannel connected");
    },
    disconnected: function() {
      return console.log("ChatChannel disconnected");
    },
    received: function(data) {
      return console.log("ChatChannel received", data);
    },
    rejected: function() {
      return console.log("ChatChannel rejected");
    },
    away: function() {
      return this.perform("away");
    },
    status: function(status) {
      return this.perform("status", {
        status: status
      });
    }
  }
);
```

Then on your Browser console you can see the message:

> ChatChannel connected

After you load, then you can broadcast messages with:

```js
App.channels["chat"].send({ message: "Hello World" });
```

And performs an action with:

```js
App.channels["chat"].perform("status", { status: "My New Status" });
```

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
