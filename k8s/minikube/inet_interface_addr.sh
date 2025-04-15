#!/bin/bash

DEFAULT_INTERFACE=$(ip route | grep default | awk '{print $5}')
HOST_IP=$(ip addr show $DEFAULT_INTERFACE | grep -E "inet " | awk '{print $2}' | cut -d/ -f1)
echo "인터넷 연결 인터페이스: $DEFAULT_INTERFACE, IP 주소: $HOST_IP"
