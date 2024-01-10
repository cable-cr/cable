# Multi-Backend example

This is an example Turbo+Cable app to demo the use of multiple backends with the Cable shard.

## Installation

To use the Redis and NATS backends, you will need to have access to running
Redis and NATS servers. A package manager for your operating system can simplify
the installation of them on your machine.

If you don't want to install a NATS server, you can use publicly available servers. For example, there is a public NATS server available at `demo.nats.io` — just don't use it for production. 😄

Once you have Redis and NATS installed, install the Crystal dependencies:

```shell
shards install
```

## Usage

To use either backend, specify the url in the `CABLE_BACKEND_URL` environment variable:

```shell
CABLE_BACKEND_URL=redis:///
CABLE_BACKEND_URL=nats:///
CABLE_BACKEND_URL=nats://demo.nats.io/
```

If you would like to see the messages passing through Redis when using the Redis backend, you can use the Redis CLI with the following command:

```shell
redis-cli subscribe time
```

If you would like to see the messages passing through NATS when using the NATS backend, you can use the [NATS CLI](https://github.com/nats-io/natscli), which may need to be installed separately from the NATS server.

```shell
nats sub time
```
