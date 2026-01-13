#!/bin/bash
kill -9 $(lsof -t -i:4000) 2>/dev/null
pkill -f "node1@127.0.0.1" 2>/dev/null
echo "❌ Node 1 killed (port 4000)"
