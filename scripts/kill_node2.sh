#!/bin/bash
kill -9 $(lsof -t -i:4001) 2>/dev/null
pkill -f "node2@127.0.0.1" 2>/dev/null
echo "❌ Node 2 killed (port 4001)"
