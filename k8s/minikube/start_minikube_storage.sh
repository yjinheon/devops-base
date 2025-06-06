#!/bin/bash

######################
# Create The Cluster #
######################
# Rook-Ceph 클러스터를 위한 minikube 설정
# KVM2 드라이버 사용 및 각 노드에 추가 디스크 구성

# 3개 노드, 각 노드에 추가디스크
minikube start \
  --cpus 2 \
  --memory 4096 \
  --nodes 3 \
  --disk-size 5g \
  --driver kvm2 \
  --extra-disks=1 \
  --profile storage-test

# 필요한 애드온 활성화
minikube addons enable ingress --profile storage-test

echo "Cluster is ready for Rook-Ceph installation"
