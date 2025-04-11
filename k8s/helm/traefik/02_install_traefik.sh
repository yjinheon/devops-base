#!/bin/bash

HELM_REPO_PATH=~/helm-repo

helm install $HELM_REPO_PATH/traefik -f traefik/my-values.yaml
