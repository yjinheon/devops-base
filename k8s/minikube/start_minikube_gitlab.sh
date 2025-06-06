#!/bin/bash

minikube start \
  --driver=virtualbox \
  --cpus 4 \
  --memory 8192 \
  --profile=gitlab

minikube addons enable ingress --profile=gitlab
minikube addons enable dashboard --profile=gitlab
