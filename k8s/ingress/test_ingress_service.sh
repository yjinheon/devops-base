#!/bin/bash

# HTTP_PORT는 Traefik의 web 엔트리포인트 NodePort
export HTTP_PORT=$(kubectl get svc -n traefik traefik -o jsonpath='{.spec.ports[?(@.name=="web")].nodePort}')

curl http://coffee.myweb.com:$HTTP_PORT

echo "----------------------------------------"

export HTTPS_PORT=$(kubectl get svc -n traefik traefik -o jsonpath='{.spec.ports[?(@.name=="websecure")].nodePort}')

curl -k https://tea.myweb.com:$HTTPS_PORT

echo "----------------------------------------"

curl -k https://www.myweb.com:$HTTPS_PORT/juice

echo "----------------------------------------"

curl -k https://www.myweb.com:$HTTPS_PORT/water
