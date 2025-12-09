# Pet Adoption

A Phoenix LiveView application for managing pet adoptions. This platform connects shelters with potential adopters, providing real-time updates and a streamlined adoption process.

## Features

- **Pet Listings** - Browse available pets with detailed profiles
- **Adoption Applications** - Submit and manage adoption requests
- **Shelter Dashboard** - Manage pets and review applications
- **Real-time Updates** - Live activity feed using Phoenix PubSub
- **Responsive UI** - Built with Tailwind CSS and DaisyUI components

## Tech Stack

- Elixir / Phoenix Framework 1.8
- Phoenix LiveView for real-time interactions
- Tailwind CSS v4 with DaisyUI
- SQLite with Ecto

## Getting Started

To start your Phoenix server:

1. Run `mix setup` to install and setup dependencies
2. Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`
3. Visit [`localhost:4000`](http://localhost:4000) from your browser

## Running Multiple Nodes (Distributed Mode)

This application supports running multiple shelter nodes in a distributed Elixir cluster. Each node represents a different shelter with its own data that syncs across the cluster.

### Start Node 1 (Happy Paws Rescue)

```bash
./start_node1.sh
# Or manually:
PORT=4000 SHELTER_NAME="Happy Paws Rescue" SHELTER_ID="shelter1" \
  iex --name node1@127.0.0.1 --cookie pet-secret -S mix phx.server
```

Visit: http://localhost:4000

### Start Node 2 (Animal Friends)

```bash
./start_node2.sh
# Or manually:
PORT=4001 SHELTER_NAME="Animal Friends" SHELTER_ID="shelter2" \
  iex --name node2@127.0.0.1 --cookie pet-secret -S mix phx.server
```

Visit: http://localhost:4001

### Start Node 3 (Rescue Haven)

```bash
./start_node3.sh
# Or manually:
PORT=4002 SHELTER_NAME="Rescue Haven" SHELTER_ID="shelter3" \
  iex --name node3@127.0.0.1 --cookie pet-secret -S mix phx.server
```

Visit: http://localhost:4002

### Connecting Nodes

Once nodes are running, connect them in any node's IEx console:

```elixir
Node.connect(:"node2@127.0.0.1")
Node.connect(:"node3@127.0.0.1")
Node.list()  # Verify connected nodes
```

## Development

- Run tests: `mix test`
- Run precommit checks: `mix precommit`
- Format code: `mix format`

## Production

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

- Official website: https://www.phoenixframework.org/
- Guides: https://hexdocs.pm/phoenix/overview.html
- Docs: https://hexdocs.pm/phoenix
- Forum: https://elixirforum.com/c/phoenix-forum
- Source: https://github.com/phoenixframework/phoenix
