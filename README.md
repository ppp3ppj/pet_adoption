# Pet Adoption

A distributed Phoenix LiveView application for managing pet adoptions across multiple shelters with automatic load balancing and fault tolerance.

## Features

- **Distributed System** - 3-node Erlang cluster with automatic data synchronization
- **Load Balancing** - Nginx-based load balancer with automatic failover
- **Pet Listings** - Browse available pets with detailed profiles
- **Adoption Applications** - Submit and manage adoption requests
- **Shelter Dashboard** - Manage pets and review applications
- **Real-time Updates** - Cross-node LiveView updates using Phoenix PubSub
- **Fault Tolerant** - Kill any node, system keeps running
- **Responsive UI** - Built with Tailwind CSS and DaisyUI components

## Tech Stack

- Elixir / Phoenix Framework 1.8
- Phoenix LiveView for real-time interactions
- Erlang Distribution for clustering
- DeltaCRDT for data synchronization
- Nginx for load balancing
- Tailwind CSS v4 with DaisyUI
- In-memory storage with snapshots

## Quick Start

### 1. Install Dependencies
```bash
mix deps.get
cd assets && npm install
```

### 2. Setup Nginx (One Time)
```bash
make install
```

### 3. Start Nodes
```bash
make all          # Start all 3 nodes
# OR start individually:
make node1        # Start node 1 (port 4000)
make node2        # Start node 2 (port 4001)
make node3        # Start node 3 (port 4002)
```

### 4. Access Application
- **http://localhost:3000** - Nginx load balancer (USE THIS!)
- **http://localhost:4000** - Node 1 (Minji-1)
- **http://localhost:4001** - Node 2 (Hearin-2)
- **http://localhost:4002** - Node 3 (Hanni-3)

## Makefile Commands

```bash
make              # Show help
make install      # Install nginx (one time)

# Start nodes
make node1        # Start node 1
make node2        # Start node 2
make node3        # Start node 3
make all          # Start all nodes

# Kill nodes
make kill1        # Kill node 1
make kill2        # Kill node 2
make kill3        # Kill node 3
make kill-all     # Kill all nodes

# Status
make status       # Check all nodes status
```

## Testing Fault Tolerance

The system demonstrates true fault tolerance:

```bash
# 1. Start all nodes
make all

# 2. Visit http://localhost:3000 and add a pet

# 3. Kill node 1
make kill1

# 4. Refresh browser - still works! (via nginx → node2/node3)

# 5. Add another pet - data syncs across remaining nodes

# 6. Restart node 1
make node1

# 7. Node 1 automatically catches up with latest data!
```

## How It Works

### Architecture

```
User Browser
     ↓
Nginx (port 3000) - Load Balancer
     ├→ Node 1 (port 4000) - Minji-1
     ├→ Node 2 (port 4001) - Hearin-2  
     └→ Node 3 (port 4002) - Hanni-3
          ↓
    DeltaCRDT Sync
    (Automatic data synchronization)
```

### Key Components

1. **Nginx Load Balancer**
   - Round-robin distribution with `least_conn`
   - Automatic health checks
   - WebSocket support for LiveView
   - Marks failed backends down after 3 failures

2. **Erlang Cluster**
   - Nodes connect via Erlang distribution
   - Automatic node discovery with libcluster
   - Shared cookie for authentication

3. **DeltaCRDT Synchronization**
   - Conflict-free data replication
   - Automatic sync every 2 seconds
   - Eventual consistency across all nodes

4. **CrdtSyncNotifier**
   - Monitors remote data changes
   - Triggers LiveView updates across nodes
   - Hash-based change detection every 1 second

5. **Snapshot Service**
   - Saves state every 5 minutes
   - Automatic restore on startup
   - Ensures data persistence

## Project Structure

```
pet_adoption/
├── lib/
│   ├── pet_adoption/
│   │   ├── crdt_store.ex           # CRDT data storage
│   │   ├── crdt_sync_notifier.ex   # Cross-node update notifier
│   │   ├── pet_manager.ex          # Pet business logic
│   │   └── application.ex          # Supervision tree
│   └── pet_adoption_web/
│       └── live/
│           ├── shelter_live/       # Shelter dashboard
│           └── public_live/        # Public adoption pages
├── scripts/
│   ├── start_node1.sh              # Start individual nodes
│   ├── kill_node1.sh               # Kill nodes
│   └── status.sh                   # Check status
├── nginx_lb.conf                   # Nginx configuration
└── Makefile                        # Easy commands
```

## Development

### View Logs
```bash
tail -f logs/node1.log
tail -f logs/node2.log
tail -f logs/node3.log
```

### Nginx Management
```bash
sudo systemctl status nginx    # Check status
sudo systemctl restart nginx   # Restart
sudo nginx -t                  # Test config
```

### Connect to Running Node
```bash
iex --name debug@127.0.0.1 --cookie pet-secret --remsh node1@127.0.0.1
```

## Learn More

- Official website: https://www.phoenixframework.org/
- Guides: https://hexdocs.pm/phoenix/overview.html
- Docs: https://hexdocs.pm/phoenix
- Forum: https://elixirforum.com/c/phoenix-forum
- Source: https://github.com/phoenixframework/phoenix
