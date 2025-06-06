#!/bin/bash

echo "add helm repo nginx"

# set helm path

HELM_REPO=~/helm-repo

helm pull bitnami/nginx --destination $HELM_REPO

echo "Helm Chart downloaded to $HELM_REPO"

tar xvfz $HELM_REPO/nginx*.tgz -C $HELM_REPO

echo "Prometheus Helm chart extracted to $HELM_REPO/nginx"
