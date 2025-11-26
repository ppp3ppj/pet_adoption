#!/bin/bash
echo "🐾 Starting Node 1..."
PORT=4000 SHELTER_NAME="Happy Paws Rescue" SHELTER_ID="shelter1" \
  iex --name node1@127.0.0.1 --cookie pet-secret -S mix phx.server
