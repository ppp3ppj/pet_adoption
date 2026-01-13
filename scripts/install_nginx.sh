#!/bin/bash

echo "📦 Installing nginx..."
sudo apt update
sudo apt install -y nginx

echo "⚙️ Configuring nginx load balancer..."
sudo cp nginx_lb.conf /etc/nginx/sites-available/pet_adoption_lb
sudo ln -sf /etc/nginx/sites-available/pet_adoption_lb /etc/nginx/sites-enabled/pet_adoption_lb
sudo rm -f /etc/nginx/sites-enabled/default

echo "✅ Testing nginx configuration..."
sudo nginx -t

if [ $? -eq 0 ]; then
    echo "🔄 Restarting nginx..."
    sudo systemctl restart nginx
    sudo systemctl enable nginx
    echo ""
    echo "✅ Nginx installed and configured!"
    echo "   Load balancer running on port 3000"
    echo "   Backends: 4000, 4001, 4002"
    echo ""
    echo "Commands:"
    echo "  sudo systemctl status nginx   # Check status"
    echo "  sudo systemctl restart nginx  # Restart"
    echo "  sudo systemctl stop nginx     # Stop"
    echo "  sudo nginx -t                 # Test config"
else
    echo "❌ Nginx configuration error!"
    exit 1
fi
