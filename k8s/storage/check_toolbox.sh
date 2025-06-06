#!/bin/bash

kubectl apply -f toolbox.yaml -n rook-ceph
kubectl -n rook-ceph wait --for=condition=ready pod -l app=rook-ceph-tools
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- bash

# Ceph toolbox commands
#ceph status
#ceph osd status
