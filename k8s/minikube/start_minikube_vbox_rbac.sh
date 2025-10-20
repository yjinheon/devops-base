#!/bin/bash

######################
# create the cluster #
######################

minikube start \
  --cpus 2 \
  --memory 4096 \
  --disk-size 20g \
  --driver virtualbox \
  --profile rbac

# 필요한 애드온 활성화
minikube addons enable ingress --profile rbac

echo "minikube started with profile rbac"
