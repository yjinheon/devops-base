#!/bin/bash

echo "*** Rook-Cluster Setup Process ***"

# Create a minikube cluster with 3 nodes using KVM2 driver
echo "*** Step 1: Creating a 3-node Minikube cluster using KVM2 driver ***"
minikube start \
  --driver=kvm2 \
  --disk-size 20g \
  --extra-disks=1

echo "*** Checking cluster status after creation ***"
minikube status
kubectl get nodes

echo "*** Starting storage device attachment process ***"

# Add storage to the first node (minikube)
echo "*** Step 2-A: Creating 5G storage device for first node (minikube) ***"
sudo -S qemu-img create -f raw /var/lib/libvirt/images/minikube-disk-5G 5G

echo "*** Step 2-B: Attaching storage device to first node (minikube) ***"
virsh -c qemu:///system attach-disk minikube --source /var/lib/libvirt/images/minikube-disk-5G --target vdx --cache none

echo "*** Step 2-C: Rebooting first node (minikube) to recognize new storage ***"
virsh -c qemu:///system reboot --domain minikube

echo "*** Waiting for first node to complete reboot (30 seconds) ***"
sleep 30

# Check if first node is back online and verify disk attachment
echo "*** Checking status of first node after reboot ***"
minikube ssh -n minikube "lsblk"

# Final step: restart the minikube cluster
echo "*** Restarting minikube cluster to ensure proper configuration ***"
minikube start

# Verify final cluster status
echo "*** Final verification: Checking cluster and storage status ***"
kubectl get nodes
echo "*** Disk status on all nodes ***"
minikube ssh -n minikube "lsblk"

echo "*** Rook-Cluster setup complete! ***"
