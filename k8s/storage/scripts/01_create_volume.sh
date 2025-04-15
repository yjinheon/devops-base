#!/bin/bash

# 각 노드에 volume 디렉토리 생성

#NODE_NAME=$(minikube profile list | storage-test | awk '{print $1}')

PROFILE_NAME=storage-test
NODE_NAME=storage-test

minikube ssh -p $PROFILE_NAME -n $NODE_NAME "sudo mkdir -p /mnt/disks/data"
minikube ssh -p $PROFILE_NAME -n $NODE_NAME "sudo chmod 777 /mnt/disks/data"

for i in $(seq 2 3); do
  minikube ssh -p $PROFILE_NAME -n $NODE_NAME-m0${i} "sudo mkdir -p /mnt/disks/data"
  minikube ssh -p $PROFILE_NAME -n $NODE_NAME-m0${i} "sudo chmod 777 /mnt/disks/data"
done
