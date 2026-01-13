# Pet Adoption - Scripts

All management scripts are in the `scripts/` directory.

## Setup (One Time)

```bash
cd scripts
chmod +x *.sh
./install_nginx.sh
```

## Start Nodes

```bash
cd scripts
./start_node1.sh    # Start node 1 on port 4000
./start_node2.sh    # Start node 2 on port 4001
./start_node3.sh    # Start node 3 on port 4002
```

## Kill Nodes

```bash
cd scripts
./kill_node1.sh     # Kill node 1
./kill_node2.sh     # Kill node 2
./kill_node3.sh     # Kill node 3
./kill_all.sh       # Kill all nodes
```

## Check Status

```bash
cd scripts
./status.sh         # Show all nodes status
```

## Access

- **http://localhost:3000** - Nginx load balancer (distributes across all nodes)
- **http://localhost:4000** - Node 1 (Shelter 1)
- **http://localhost:4001** - Node 2 (Shelter 2)
- **http://localhost:4002** - Node 3 (Shelter 3)

## Test Fault Tolerance

```bash
cd scripts
./kill_node1.sh              # Kill node 1
# Visit http://localhost:3000 - still works!
./start_node1.sh             # Restart node 1
# Nginx automatically picks it up
```

## Nginx Management

```bash
sudo systemctl status nginx   # Check status
sudo systemctl restart nginx  # Restart
sudo systemctl stop nginx     # Stop
sudo nginx -t                 # Test config
```
