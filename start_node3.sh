#!/bin/bash
echo "🐾 Starting Node 3..."
PORT=4002 SHELTER_NAME="Rescue Haven" SHELTER_ID="shelter3" \
  iex --name node3@127.0.0.1 --cookie pet-secret -S mix phx.server
