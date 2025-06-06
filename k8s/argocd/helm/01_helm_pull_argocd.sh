#!/bin/bash

echo "add helm repo argocd"

helm repo add argo https://argoproj.github.io/argo-helm

echo "update helm repo"

# set helm path

HELM_REPO=~/helm-repo

helm pull argo/argo-cd --destination $HELM_REPO

echo "argocd Helm Chard downloaded to $HELM_REPO"

tar xvfz $HELM_REPO/argo-cd-*.tgz -C $HELM_REPO

echo "argocd Helm Chart extracted to $HELM_REPO"
