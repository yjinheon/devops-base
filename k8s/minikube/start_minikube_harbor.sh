#!/bin/bash

######################
# Create The Cluster #
######################
# Rook-Ceph 클러스터를 위한 minikube 설정
# KVM2 드라이버 사용 및 각 노드에 추가 디스크 구성

minikube start \
  --cpus 4 \
  --memory 8192 \
  --driver docker \
  --profile harbor-test

# 필요한 애드온 활성화
#minikube addons enable ingress --profile harbor-test

echo "Cluster is ready for Harbor Test"
