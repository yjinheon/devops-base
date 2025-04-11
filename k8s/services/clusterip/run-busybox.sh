#!/bin/bash

# sleep 1d means the container will run for 1 day

kubectl run busybox --image=busybox:1.28 --restart=Never -- sleep 1d
