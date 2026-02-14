#!/bin/bash
STACK_NAME=${1:-"k8s-auto"}

echo "Deleting stack: $STACK_NAME..."
openstack stack delete $STACK_NAME --yes --wait
echo "Stack deleted!"
