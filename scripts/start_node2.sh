#!/bin/bash
cd "$(dirname "$0")"/..
echo "🐾 Starting Node 2..."
PORT=4001 SHELTER_NAME="Hearin-2" SHELTER_ID="shelter2" \
  iex --name node2@127.0.0.1 --cookie pet-secret -S mix phx.server
