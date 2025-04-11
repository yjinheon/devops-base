#!/bin/bash

######################
# Create The Cluster #
######################

minikube start \
  --cpus 3 \
  --memory 6900 \
  --nodes 3
#--disk-size 10g

minikube addons enable ingress
#minikube addons enable storage-provisioner
#minikube addons enable default-storageclass
