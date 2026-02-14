#!/bin/bash
# Auto-generate inventory.ini from OpenStack
# Usage: ./generate-inventory.sh <stack-name> <key-path>

STACK_NAME=${1:-"k8s-cluster"}
KEY_PATH=${2:-"~/mykey.pem"}

echo "Discovering VMs from OpenStack stack: $STACK_NAME"

# Get server details
MASTER_NAME=$(openstack server list --name ".*master.*" -f value -c Name | head -1)
MASTER_FLOATING=$(openstack server show "$MASTER_NAME" -f value -c addresses | grep -oP '192\.168\.\d+\.\d+')
MASTER_PRIVATE=$(openstack server show "$MASTER_NAME" -f value -c addresses | grep -oP '10\.\d+\.\d+\.\d+')

echo "Master: $MASTER_NAME - Floating: $MASTER_FLOATING - Private: $MASTER_PRIVATE"

# Generate inventory
cat > inventory.ini << INVEOF
[masters]
$MASTER_NAME ansible_host=$MASTER_FLOATING private_ip=$MASTER_PRIVATE

[workers]
INVEOF

# Get all workers
for WORKER in $(openstack server list --name ".*worker.*" -f value -c Name); do
    WORKER_FLOATING=$(openstack server show "$WORKER" -f value -c addresses | grep -oP '192\.168\.\d+\.\d+')
    WORKER_PRIVATE=$(openstack server show "$WORKER" -f value -c addresses | grep -oP '10\.\d+\.\d+\.\d+')
    echo "$WORKER ansible_host=$WORKER_FLOATING private_ip=$WORKER_PRIVATE" >> inventory.ini
    echo "Worker: $WORKER - Floating: $WORKER_FLOATING - Private: $WORKER_PRIVATE"
done

cat >> inventory.ini << INVEOF

[k8s_cluster:children]
masters
workers

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=$KEY_PATH
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
INVEOF

echo ""
echo "=== Generated inventory.ini ==="
cat inventory.ini
echo ""
echo "=== Ready to deploy ==="
echo "Run: ansible-playbook -i inventory.ini site.yml"
