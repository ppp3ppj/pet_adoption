#!/bin/bash
pkill -f "node[123]@127.0.0.1"
kill -9 $(lsof -t -i:4000) 2>/dev/null
kill -9 $(lsof -t -i:4001) 2>/dev/null
kill -9 $(lsof -t -i:4002) 2>/dev/null
echo "❌ All nodes killed"
