#!/bin/bash
cd "$(dirname "$0")"/.. || exit
echo "🐾 Starting Node 3..."
PORT=4002 SHELTER_NAME="Hanni-3" SHELTER_ID="shelter3" \
  iex --name node3@127.0.0.1 --cookie pet-secret -S mix phx.server
