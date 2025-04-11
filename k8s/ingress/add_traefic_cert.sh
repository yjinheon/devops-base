#!/bin/bash

echo "Adding Traefik certificate to the cluster..."
echo "Creating a self-signed certificate for Traefik..."

# -subj 옵션으로 인증서 정보 설정
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout myweb01.key \
  -out myweb01.crt \
  -subj "/C=KR/ST=Seoul/L=Seoul/O=MyOrganization/OU=IT/CN=myweb01.example.com"

echo "인증서 생성 완료"

echo "인증서 권한 변경..."
sudo chmod 644 myweb01.key

echo "Creating a secret for Traefik..."
kubectl create secret tls myweb-tls \
  --cert=myweb01.crt \
  --key=myweb01.key \
  -n kube-system

echo "인증서 및 시크릿 생성 완료"
