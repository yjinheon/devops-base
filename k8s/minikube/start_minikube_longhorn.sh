#!/bin/bash

minikube start --driver=docker \
  --cpus=4 \
  --memory=8g \
  --disk-size=20g \
  --profile=longhorn-test
