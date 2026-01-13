#!/bin/bash
mkdir -p logs

# Start 3 Phoenix nodes
PORT=4000 SHELTER_NAME="Shelter 1" SHELTER_ID="shelter1" PHX_SERVER=true \
  elixir --name node1@127.0.0.1 --cookie secret -S mix phx.server > logs/node1.log 2>&1 &
sleep 3

PORT=4001 SHELTER_NAME="Shelter 2" SHELTER_ID="shelter2" PHX_SERVER=true \
  elixir --name node2@127.0.0.1 --cookie secret -S mix phx.server > logs/node2.log 2>&1 &
sleep 3

PORT=4002 SHELTER_NAME="Shelter 3" SHELTER_ID="shelter3" PHX_SERVER=true \
  elixir --name node3@127.0.0.1 --cookie secret -S mix phx.server > logs/node3.log 2>&1 &
sleep 3

echo "✅ Started 3 Phoenix nodes:"
echo "   http://localhost:4000  <- Node 1 (Shelter 1)"
echo "   http://localhost:4001  <- Node 2 (Shelter 2)"
echo "   http://localhost:4002  <- Node 3 (Shelter 3)"
echo ""
echo "📌 Nginx load balancer:"
echo "   http://localhost:3000  <- Nginx (auto load balance)"
echo ""
echo "Test fault tolerance:"
echo "  kill -9 \$(lsof -t -i:4000)  # Kill node 1"
echo "  # Nginx will automatically route to 4001/4002"
echo ""
echo "Stop all: ./stop_nginx.sh"
