#!/bin/bash
kill -9 $(lsof -t -i:4002) 2>/dev/null
pkill -f "node3@127.0.0.1" 2>/dev/null
echo "❌ Node 3 killed (port 4002)"
