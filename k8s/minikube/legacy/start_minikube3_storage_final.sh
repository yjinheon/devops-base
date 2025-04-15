#!/bin/bash
######################
# Create The Cluster #
######################
# Rook-Ceph 클러스터를 위한 minikube 설정
# KVM2 드라이버 사용 및 각 노드에 추가 디스크 구성

# 기존 클러스터가 있다면 정리
minikube delete --profile storage-test

# 3개 노드로 구성된 클러스터 생성, 각 노드에 추가 디스크 할당
minikube start \
  --cpus 2 \
  --memory 4096 \
  --nodes 3 \
  --disk-size 20g \
  --driver kvm2 \
  --extra-disks=1 \
  --profile storage-test

# 필요한 애드온 활성화
minikube addons enable ingress --profile storage-test

# 각 노드에서 디스크 준비 작업 수행
NODE_NAMES=("storage-test" "storage-test-m02" "storage-test-m03")
for node in "${NODE_NAMES[@]}"; do
  echo "===== Preparing disks on node $node ====="

  # 디스크 확인
  minikube ssh --profile storage-test --node $node "lsblk"

  # 추가 디스크 찾기 (vda는 OS 디스크이므로 제외)
  # minikube에서 추가 디스크는 일반적으로 vdb로 생성됨
  minikube ssh --profile storage-test --node $node "sudo wipefs -a /dev/vdb || echo 'Disk not found or error while wiping'"

  # 디스크 권한 설정
  minikube ssh --profile storage-test --node $node "sudo chmod 666 /dev/vdb || echo 'Error setting permissions'"

  # 확인
  minikube ssh --profile storage-test --node $node "ls -la /dev/vd*"
done

echo "Cluster is ready for Rook-Ceph installation"
