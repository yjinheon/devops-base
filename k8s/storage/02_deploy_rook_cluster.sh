#!/bin/bash

kubectl create -f crds.yaml &&
  kubectl create -f common.yaml &&
  kubectl create -f operator.yaml
