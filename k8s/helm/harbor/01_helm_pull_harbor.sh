#!/bin/bash

echo "add helm repo harbor"

helm repo add harbor https://helm.goharbor.io

echo "update helm repo"

# set helm path

HELM_REPO=~/helm-repo

helm pull harbor/harbor --destination $HELM_REPO

echo "Harbor Helm Chard downloaded to $HELM_REPO"

tar xvfz $HELM_REPO/harbor*.tgz -C $HELM_REPO

echo "Harbor Helm chart extracted to $HELM_REPO/harbor"
