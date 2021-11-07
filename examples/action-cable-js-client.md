If you are using Rails, then you already has a `app/assets/javascripts/cable.js` file that requires `action_cable`,
you just need to connect to the right URL (don't forgot the settings you used), to authenticate using JWT use something like:

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
