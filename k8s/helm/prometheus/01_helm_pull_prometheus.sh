#!/bin/bash

echo "add helm repo prometheus"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

echo "update helm repo"

# set helm path

HELM_REPO=~/helm-repo

helm pull prometheus-community/kube-prometheus-stack --destination $HELM_REPO

echo "Prometheus Helm Chart downloaded to $HELM_REPO"

tar xvfz $HELM_REPO/kube-prometheus-stack*.tgz -C $HELM_REPO

echo "Prometheus Helm chart extracted to $HELM_REPO/kube-prometheus-stack"
