#!/bin/sh

# Source: http://kubernetes.io/docs/getting-started-guides/kubeadm

set -e

# Color codes
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}[INFO] Verify ubuntu release...${NC}"
source /etc/lsb-release
if [ "$DISTRIB_RELEASE" != "24.04" ]; then
    echo "################################# "
    echo "############ WARNING ############ "
    echo "################################# "
    echo
    echo "This script only works on Ubuntu 24.04!"
    echo "You're using: ${DISTRIB_DESCRIPTION}"
    echo "Better ABORT with Ctrl+C. Or press any key to continue the install"
    read
fi

echo
echo -e "${GREEN}[INFO] specify kubernetes version...${NC}"
# Kubernetes Variable Declaration
#KUBERNETES_VERSION="v1.32"
#CRIO_VERSION="v1.32"
#KUBERNETES_INSTALL_VERSION="1.32.0-1.1"

echo


echo -e "${GREEN}[INFO] get platform...${NC}"
# get platform
PLATFORM=`uname -p`

if [ "${PLATFORM}" == "aarch64" ]; then
  PLATFORM="arm64"
elif [ "${PLATFORM}" == "x86_64" ]; then
  PLATFORM="amd64"
else
  echo "${PLATFORM} has to be either amd64 or arm64/aarch64. Check containerd supported binaries page"
  echo "https://github.com/containerd/containerd/blob/main/docs/getting-started.md#option-1-from-the-official-binaries"
#  exit 1
fi

echo

echo -e "${GREEN}[INFO] setup vimrc, bashrc, and terminal...${NC}"
### setup terminal
sudo apt-get --allow-unauthenticated update
sudo apt-get --allow-unauthenticated install -y bash-completion binutils
echo 'colorscheme ron' >> ~/.vimrc
echo 'set tabstop=2' >> ~/.vimrc
echo 'set shiftwidth=2' >> ~/.vimrc
echo 'set expandtab' >> ~/.vimrc
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'alias k=kubectl' >> ~/.bashrc
echo 'alias c=clear' >> ~/.bashrc
echo 'complete -F __start_kubectl k' >> ~/.bashrc
sed -i '1s/^/force_color_prompt=yes\n/' ~/.bashrc



### init k8s
echo -e "${GREEN}[INFO] initialize kubernetes...${NC}"
sudo rm /root/.kube/config || true


#!/bin/bash

# Variables
CONTROL_PLANE_ENDPOINT="master-node" # Use hostname for the control-plane endpoint
POD_CIDR="192.168.0.0/16"
CRI_SOCKET="unix:///var/run/containerd/containerd.sock" # Specify containerd runtime explicitly

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Ensure kubeadm is installed
if ! command -v kubeadm &> /dev/null; then
    echo -e "${RED}[ERROR] kubeadm is not installed. Please ensure kubeadm, kubelet, and kubectl are installed.${NC}"
    return
fi

# Pull required images
echo -e "${YELLOW}[INFO] Pulling required images for kubeadm...${NC}"
if ! sudo kubeadm config images pull; then
    echo -e "${RED}[ERROR] Failed to pull kubeadm images. Check your network and configuration.${NC}"
    return
fi

# Initialize kubeadm with hostname as control-plane endpoint
echo -e "${YELLOW}[INFO] Initializing kubeadm with control-plane-endpoint: ${CONTROL_PLANE_ENDPOINT}${NC}"
if ! sudo kubeadm init \
    --control-plane-endpoint="${CONTROL_PLANE_ENDPOINT}:6443" \
    --pod-network-cidr="${POD_CIDR}" \
    --cri-socket="${CRI_SOCKET}" \
    --ignore-preflight-errors Swap; then
    echo -e "${RED}[ERROR] kubeadm initialization failed. Check your logs for details.${NC}"
    return
fi

# Configure kubeconfig
if [ -f /etc/kubernetes/admin.conf ]; then
    echo -e "${YELLOW}[INFO] Configuring kubeconfig...${NC}"
    mkdir -p "$HOME/.kube"
    if sudo cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"; then
        sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
        echo -e "${GREEN}[SUCCESS] Kubeconfig set up successfully.${NC}"
    else
        echo -e "${RED}[ERROR] Failed to copy kubeconfig. Check permissions and try again.${NC}"
    fi
else
    echo -e "${RED}[ERROR] /etc/kubernetes/admin.conf does not exist. Ensure kubeadm init completed successfully.${NC}"
fi



### CNI
# Install Kubernetes Network Plugin (Calico)
# https://github.com/projectcalico/calico/releases
# https://kifarunix.com/install-and-setup-kubernetes-cluster-on-ubuntu-24-04/
#CNI_VER=3.28.0
#echo -e "${GREEN}[INFO] install calico network plugin...${NC}"
#kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v${CNI_VER}/manifests/tigera-operator.yaml
#
#wget https://raw.githubusercontent.com/projectcalico/calico/v${CNI_VER}/manifests/custom-resources.yaml
#
#kubectl create -f custom-resources.yaml

sudo kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

sleep 10


echo
echo "### COMMAND TO ADD A WORKER NODE ###"
echo
echo -e "${GREEN}[INFO] create join command...${NC}"
kubeadm token create --print-join-command --ttl 0