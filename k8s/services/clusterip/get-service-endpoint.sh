#!/bin/bash

# get service endpoint

kubectl get endpoints | grep -v NAME | fzf | awk '{print $2}'
