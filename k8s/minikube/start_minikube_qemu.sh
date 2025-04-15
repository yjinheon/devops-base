#!/bin/bash

echo "*** Rook-Cluster Setup Process ***"

# Create a minikube cluster with 3 nodes using KVM2 driver
echo "*** Step 1: Creating a 3-node Minikube cluster using KVM2 driver ***"
minikube start --driver=kvm2 --nodes 3

echo "*** Checking cluster status after creation ***"
minikube status
kubectl get nodes

echo "*** Starting storage device attachment process ***"

# Add storage to the first node (minikube)
echo "*** Step 2-A: Creating 5G storage device for first node (minikube) ***"
sudo -S qemu-img create -f raw /var/lib/libvirt/images/minikube-disk-1G 5G

echo "*** Step 2-B: Attaching storage device to first node (minikube) ***"
virsh -c qemu:///system attach-disk minikube --source /var/lib/libvirt/images/minikube-disk-1G --target vdx --cache none

echo "*** Step 2-C: Rebooting first node (minikube) to recognize new storage ***"
virsh -c qemu:///system reboot --domain minikube

echo "*** Waiting for first node to complete reboot (30 seconds) ***"
sleep 30

# Check if first node is back online and verify disk attachment
echo "*** Checking status of first node after reboot ***"
minikube ssh -n minikube "lsblk"

# Add storage to the second node (minikube-m02)
echo "*** Step 3-A: Creating 5G storage device for second node (minikube-m02) ***"
sudo -S qemu-img create -f raw /var/lib/libvirt/images/minikube-m02-disk-2G 5G

echo "*** Step 3-B: Attaching storage device to second node (minikube-m02) ***"
virsh -c qemu:///system attach-disk minikube-m02 --source /var/lib/libvirt/images/minikube-m02-disk-2G --target vdy --cache none

echo "*** Step 3-C: Rebooting second node (minikube-m02) to recognize new storage ***"
virsh -c qemu:///system reboot --domain minikube-m02

echo "*** Waiting for second node to complete reboot (30 seconds) ***"
sleep 30

# Check if second node is back online and verify disk attachment
echo "*** Checking status of second node after reboot ***"
minikube ssh -n minikube-m02 "lsblk"

# Add storage to the third node (minikube-m03)
echo "*** Step 4-A: Creating 5G storage device for third node (minikube-m03) ***"
sudo -S qemu-img create -f raw /var/lib/libvirt/images/minikube-m03-disk-3G 5G

echo "*** Step 4-B: Attaching storage device to third node (minikube-m03) ***"
virsh -c qemu:///system attach-disk minikube-m03 --source /var/lib/libvirt/images/minikube-m03-disk-3G --target vdz --cache none

echo "*** Step 4-C: Rebooting third node (minikube-m03) to recognize new storage ***"
virsh -c qemu:///system reboot --domain minikube-m03

echo "*** Waiting for third node to complete reboot (30 seconds) ***"
sleep 30

# Check if third node is back online and verify disk attachment
echo "*** Checking status of third node after reboot ***"
minikube ssh -n minikube-m03 "lsblk"

# Final step: restart the minikube cluster
echo "*** Step 5: Restarting minikube cluster to ensure proper configuration ***"
minikube start

# Verify final cluster status
echo "*** Final verification: Checking cluster and storage status ***"
kubectl get nodes
echo "*** Disk status on all nodes ***"
minikube ssh -n minikube "lsblk"
minikube ssh -n minikube-m02 "lsblk"
minikube ssh -n minikube-m03 "lsblk"

echo "*** Rook-Cluster setup complete! ***"
