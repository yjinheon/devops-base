#!/bin/bash

# 사전수행필요

#systemctl start libvirtd
#systemctl start squid

# 기본 인터페이스 찾기
DEFAULT_INTERFACE=$(ip route | grep default | awk '{print $5}')

# 기본 인터페이스의 IP 주소 찾기
HOST_IP=$(ip addr show $DEFAULT_INTERFACE | grep -E "inet " | awk '{print $2}' | cut -d/ -f1)

echo "호스트 머신 정보:"
echo "- 인터넷 연결 인터페이스: $DEFAULT_INTERFACE"
echo "- IP 주소: $HOST_IP"

# 프록시 설정
PROXY_PORT="3128"
PROXY_URL="http://${HOST_IP}:${PROXY_PORT}"

# NO_PROXY settings
NO_PROXY_LIST="localhost,127.0.0.1,10.96.0.0/12,192.168.59.0/24,192.168.49.0/24,192.168.39.0/24,192.168.50.0/24"

echo "Using proxy: ${PROXY_URL}"

# Setting environment variables for the current shell
export HTTP_PROXY="${PROXY_URL}"
export HTTPS_PROXY="${PROXY_URL}"
export NO_PROXY="${NO_PROXY_LIST}"

# Start Minikube with the correct proxy settings
echo "Starting Minikube with proxy settings..."

echo "proxy URL: ${PROXY_URL}"
minikube start --disk-size=15g \
  --extra-disks=1 \
  --driver kvm2 \
  --docker-env HTTP_PROXY="${PROXY_URL}" \
  --docker-env HTTPS_PROXY="${PROXY_URL}" \
  --docker-env NO_PROXY="${NO_PROXY_LIST}"

#minikube addons enable registry-creds
#minikube addons configure registry-creds

# 시작 성공 여부 확인
if [ $? -eq 0 ]; then
  echo "Minikube가 성공적으로 시작되었습니다!"
else
  echo "Minikube 시작 중 오류가 발생했습니다."
  echo "로그를 확인하세요: minikube logs"
fi
