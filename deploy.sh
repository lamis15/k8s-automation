#!/bin/bash
set -e

STACK_NAME=${1:-"k8s-auto"}
KEY_PATH=${2:-"~/mykey.pem"}

echo "======================================"
echo "  FULLY AUTOMATED K8S DEPLOYMENT"
echo "======================================"

# ========== STEP 1: Create Heat Stack ==========
echo "[1/5] Creating Heat stack: $STACK_NAME..."
openstack stack create -t heat-template.yaml --parameter StackPrefix=$STACK_NAME --wait $STACK_NAME

echo "[1/5] Stack created successfully!"

# ========== STEP 2: Get IPs from Stack ==========
echo "[2/5] Getting IPs from stack outputs..."

MASTER_FIP=$(openstack stack output show $STACK_NAME master_floating_ip -f value -c output_value)
MASTER_PIP=$(openstack stack output show $STACK_NAME master_private_ip -f value -c output_value)
WORKER1_FIP=$(openstack stack output show $STACK_NAME worker1_floating_ip -f value -c output_value)
WORKER1_PIP=$(openstack stack output show $STACK_NAME worker1_private_ip -f value -c output_value)
WORKER2_FIP=$(openstack stack output show $STACK_NAME worker2_floating_ip -f value -c output_value)
WORKER2_PIP=$(openstack stack output show $STACK_NAME worker2_private_ip -f value -c output_value)

echo "Master:   $MASTER_FIP ($MASTER_PIP)"
echo "Worker-1: $WORKER1_FIP ($WORKER1_PIP)"
echo "Worker-2: $WORKER2_FIP ($WORKER2_PIP)"

# ========== STEP 3: Generate Inventory ==========
echo "[3/5] Generating inventory.ini..."

cat > inventory.ini << INVEOF
[masters]
${STACK_NAME}-master ansible_host=$MASTER_FIP private_ip=$MASTER_PIP

[workers]
${STACK_NAME}-worker-1 ansible_host=$WORKER1_FIP private_ip=$WORKER1_PIP
${STACK_NAME}-worker-2 ansible_host=$WORKER2_FIP private_ip=$WORKER2_PIP

[k8s_cluster:children]
masters
workers

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=$KEY_PATH
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
INVEOF

echo "Inventory generated:"
cat inventory.ini

# ========== STEP 4: Wait for VMs ==========
echo "[4/5] Waiting for VMs to be reachable..."

for IP in $MASTER_FIP $WORKER1_FIP $WORKER2_FIP; do
    echo -n "Waiting for $IP..."
    until ssh -i $KEY_PATH -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@$IP "echo ready" 2>/dev/null; do
        echo -n "."
        sleep 10
    done
    echo " OK!"
done

echo "All VMs are ready!"

# ========== STEP 5: Run Ansible ==========
echo "[5/5] Running Ansible playbook..."
ansible-playbook -i inventory.ini site.yml

echo ""
echo "======================================"
echo "  DEPLOYMENT COMPLETE!"
echo "======================================"
echo "Grafana:      http://$MASTER_FIP:30300 (admin/admin)"
echo "Prometheus:   http://$MASTER_FIP:30090"
echo "Alertmanager: http://$MASTER_FIP:30093"
echo "Demo App:     http://$MASTER_FIP:30080"
echo "======================================"
