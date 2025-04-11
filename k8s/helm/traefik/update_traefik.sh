#!/bin/bash

# 대시보드 활성화 및 IngressRoute 사용 설정
helm upgrade traefik traefik/traefik \
  --set dashboard.enable=true \
  --set dashboard.ingressRoute=true \
  --set ports.traefik.expose=true \
  --set service.type=NodePort
