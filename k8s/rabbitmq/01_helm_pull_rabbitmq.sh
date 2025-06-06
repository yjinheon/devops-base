#!/bin/bash

#echo "add helm repo argocd"
#helm repo add argo https://argoproj.github.io/argo-helm

echo "update helm repo"

# set helm path

HELM_REPO=~/helm-repo

helm pull bitnami/rabbitmq --destination $HELM_REPO

echo "argocd Helm Chard downloaded to $HELM_REPO"

tar xvfz $HELM_REPO/rabbitmq-*.tgz -C $HELM_REPO

echo "argocd rabbitmq Chart extracted to $HELM_REPO"
