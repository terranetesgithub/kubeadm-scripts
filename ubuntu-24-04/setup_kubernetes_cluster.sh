#!/bin/bash

#sudo launchctl kickstart -k system/com.canonical.multipassd
#
## Authenticate with Multipass
#echo -e "\033[1;32mAuthenticating with Multipass...\033[0m"
#multipass authenticate
#
#if [[ $? -ne 0 ]]; then
#  echo -e "\033[1;31mFailed to authenticate with Multipass. Please check your credentials.\033[0m"
#  exit 1
#fi

# Color codes
GREEN='\033[0;32m'
NC='\033[0m' # No Color

##############################################################
## Deploy k8s cluster on the master node
##############################################################
echo -e "${GREEN}[INFO] Deploying Kubernetes on master node...${NC}"
multipass exec master-node -- sudo bash -c "$(curl -s https://raw.githubusercontent.com/killer-sh/cks-course-environment/refs/heads/master/cluster-setup/latest/install_master.sh)"

# Get join command from master node
echo -e "${GREEN}[INFO] Retrieving join command from master node...${NC}"
JOIN_COMMAND=$(multipass exec master-node -- sudo kubeadm token create --print-join-command)

if [ -z "$JOIN_COMMAND" ]; then
    echo -e "${GREEN}[ERROR] Failed to retrieve join command from master node.${NC}"
    exit 1
fi

##############################################################
## Deploy k8s cluster on the worker nodes
##############################################################
for worker in worker-node-1 worker-node-2; do
    echo -e "${GREEN}[INFO] Deploying Kubernetes on $worker...${NC}"
    multipass exec $worker -- sudo bash -c "$(curl -s https://raw.githubusercontent.com/killer-sh/cks-course-environment/refs/heads/master/cluster-setup/latest/install_worker.sh)"

    echo -e "${GREEN}[INFO] Joining $worker to the cluster...${NC}"
    # Use 'sudo bash -c' to ensure the environment is fully loaded
    multipass exec $worker -- sudo bash -c "$JOIN_COMMAND"
done

echo -e "${GREEN}[INFO] Kubernetes cluster deployed successfully.${NC}"

##############################################################
## Update local kubeconfig
##############################################################
echo -e "${GREEN}[INFO] Updating local kubeconfig...${NC}"

KUBECONFIG_PATH="$HOME/.kube/config"

# Function to retrieve kubeconfig
get_kubeconfig() {
    local master_ip="$1"
    echo -e "${GREEN}Attempting to fetch kubeconfig from $master_ip...${NC}"
    mkdir -p "$HOME/.kube"
    # Remove existing kubeconfig before fetching a new one
    if [ -f "$KUBECONFIG_PATH" ]; then
        echo -e "${GREEN}[INFO] Removing existing kubeconfig at $KUBECONFIG_PATH...${NC}"
        rm -f "$KUBECONFIG_PATH"
    fi
    # Fetch kubeconfig from the master node
    if multipass exec master-node -- sudo cat /etc/kubernetes/admin.conf > "$KUBECONFIG_PATH"; then
        chmod 600 "$KUBECONFIG_PATH"
        echo -e "${GREEN}Successfully copied kubeconfig from master node.${NC}"
        return 0
    else
        echo -e "${GREEN}Failed to copy kubeconfig from master node.${NC}"
        return 1
    fi
}

# Get the master IP
MASTER_IP=$(multipass info master-node | grep IPv4 | awk '{print $2}')
if [ -z "$MASTER_IP" ]; then
    echo -e "${GREEN}Error: Unable to determine master node IP.${NC}"
    exit 1
fi

# Attempt to fetch kubeconfig
if get_kubeconfig "$MASTER_IP"; then
    if KUBECONFIG="$KUBECONFIG_PATH" kubectl get nodes; then
        echo -e "${GREEN}Successfully retrieved nodes after fetching new kubeconfig.${NC}"
    else
        echo -e "${GREEN}Error: Failed to get nodes even after fetching new kubeconfig.${NC}"
        echo -e "${GREEN}kubectl get nodes output:${NC}"
        KUBECONFIG="$KUBECONFIG_PATH" kubectl get nodes
        exit 1
    fi
else
    echo -e "${GREEN}Error: Failed to retrieve kubeconfig. Please check your master node accessibility.${NC}"
    exit 1
fi

echo -e "${GREEN}Kubernetes cluster deployment and configuration completed successfully.${NC}"

echo -e "${GREEN}Sleeping for 10 seconds for stability...${NC}"
sleep 10

# Verify cluster status
echo -e "${GREEN}Verifying cluster status...${NC}"
sudo kubectl get nodes

echo -e "${GREEN}Verifying pods across all namespaces...${NC}"
sudo kubectl get pod -A