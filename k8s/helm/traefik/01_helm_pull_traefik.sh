#!/bin/bash

#helm repo add traefik https://helm.traefik.io/traefik

# set helm path

HELM_REPO=~/helm-repo

helm pull traefik/traefik --destination $HELM_REPO

echo "Traefik Helm chart downloaded to $HELM_REPO"

tar xvfz $HELM_REPO/traefik-*.tgz -C $HELM_REPO

echo "Traefik Helm chart extracted to $HELM_REPO/traefik"
