#!/bin/bash

helm install registry harbor/harbor \
  --namespace harbor \
  --set expose.type="clusterIP" \
  --set expose.tls.enabled="false" \
  --set registry.relativeurls="true" \
  --set expose.clusterIP.name="harbor" \
  --set expose.clusterIP.ports.httpPort="8080" \
  --set externalURL="http://harbor.devops.svc:8080" \
  --set harborAdminPassword="admin" \
  --set registry.credentials.username="admin" \
  --set registry.credentials.password="admin"
