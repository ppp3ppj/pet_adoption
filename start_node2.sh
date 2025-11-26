#!/bin/bash
echo "🐾 Starting Node 2..."
PORT=4001 SHELTER_NAME="Animal Friends" SHELTER_ID="shelter2" \
  iex --name node2@127.0.0.1 --cookie pet-secret -S mix phx.server
