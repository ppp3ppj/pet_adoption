#!/bin/bash
pkill -f "node[123]@127.0.0.1"
echo "✅ All Phoenix nodes stopped"
echo ""
echo "💡 Nginx is still running. To stop nginx:"
echo "   sudo systemctl stop nginx"
