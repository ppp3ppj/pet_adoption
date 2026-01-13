.PHONY: help install node1 node2 node3 all kill1 kill2 kill3 kill-all status setup

help:
	@echo "Pet Adoption - Node Management"
	@echo ""
	@echo "Setup:"
	@echo "  make setup       Make scripts executable (run first!)"
	@echo "  make install     Install nginx"
	@echo ""
	@echo "Start nodes:"
	@echo "  make node1       Start node 1 (port 4000)"
	@echo "  make node2       Start node 2 (port 4001)"
	@echo "  make node3       Start node 3 (port 4002)"
	@echo "  make all         Start all nodes"
	@echo ""
	@echo "Kill nodes:"
	@echo "  make kill1       Kill node 1"
	@echo "  make kill2       Kill node 2"
	@echo "  make kill3       Kill node 3"
	@echo "  make kill-all    Kill all nodes"
	@echo ""
	@echo "Status:"
	@echo "  make status      Check all nodes status"

setup:
	@chmod +x scripts/*.sh
	@echo "✅ Scripts are now executable"

install: setup
	@cd scripts && ./install_nginx.sh

node1: setup
	@cd scripts && ./start_node1.sh

node2: setup
	@cd scripts && ./start_node2.sh

node3: setup
	@cd scripts && ./start_node3.sh

all: setup
	@cd scripts && ./start_node1.sh
	@sleep 3
	@cd scripts && ./start_node2.sh
	@sleep 3
	@cd scripts && ./start_node3.sh

kill1: setup
	@cd scripts && ./kill_node1.sh

kill2: setup
	@cd scripts && ./kill_node2.sh

kill3: setup
	@cd scripts && ./kill_node3.sh

kill-all: setup
	@cd scripts && ./kill_all.sh

status: setup
	@cd scripts && ./status.sh
