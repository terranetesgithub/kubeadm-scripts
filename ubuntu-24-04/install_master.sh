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

echo


#!/bin/bash

# Kubernetes Variable Declaration
KUBERNETES_VERSION="v1.32"
CRIO_VERSION="v1.32"
KUBERNETES_INSTALL_VERSION="1.32.0-1.1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Apply sysctl params without reboot
echo -e "${YELLOW}[INFO] Applying sysctl parameters without reboot...${NC}"
sudo sysctl --system


############################################################################################################
# Install kubeadm, kubelet, and kubectl
############################################################################################################

# Install kubelet, kubectl, and kubeadm
echo -e "${YELLOW}[INFO] Installing kubelet, kubectl, and kubeadm...${NC}"
curl -fsSL https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/Release.key | \
    gpg --dearmor | sudo tee /etc/apt/keyrings/kubernetes-apt-keyring.gpg > /dev/null

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/ /" | \
    sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update -y

# Handle held Kubernetes packages
echo -e "${YELLOW}[INFO] Removing package hold on kubelet, kubectl, and kubeadm...${NC}"
sudo apt-mark unhold kubelet kubectl kubeadm

sudo apt-get install -y --allow-change-held-packages kubelet="$KUBERNETES_INSTALL_VERSION" \
    kubectl="$KUBERNETES_INSTALL_VERSION" kubeadm="$KUBERNETES_INSTALL_VERSION"

# Reapply package hold
sudo apt-mark hold kubelet kubectl kubeadm

# Verify installation and versions
echo -e "${YELLOW}[INFO] Verifying installation of kubeadm, kubectl, and kubelet...${NC}"
if command -v kubeadm &> /dev/null; then
    echo -e "${GREEN}[SUCCESS] kubeadm version: $(kubeadm version -o short)${NC}"
else
    echo -e "${RED}[ERROR] kubeadm is not installed successfully.${NC}"
fi

if command -v kubectl &> /dev/null; then
    echo -e "${GREEN}[SUCCESS] kubectl version: $(kubectl version --client --short)${NC}"
else
    echo -e "${RED}[ERROR] kubectl is not installed successfully.${NC}"
fi

if command -v kubelet &> /dev/null; then
    echo -e "${GREEN}[SUCCESS] kubelet version: $(kubelet --version)${NC}"
else
    echo -e "${RED}[ERROR] kubelet is not installed successfully.${NC}"
fi

sudo apt-get update -y

# Install jq, a command-line JSON processor
sudo apt-get install -y jq

# Retrieve the local IP address dynamically
local_ip="$(ip --json addr show | jq -r '.[] | select(.ifname != null) | .addr_info[] | select(.family == "inet") | .local' | head -n 1)"

# Verify if a valid IP address was retrieved
if [ -z "$local_ip" ]; then
  echo -e "${RED}[ERROR] Unable to retrieve the local IP address. Please ensure a valid network interface is active.${NC}"
else
  # Write the local IP address to the kubelet default configuration file with sufficient permissions
  sudo tee /etc/default/kubelet > /dev/null << EOF
KUBELET_EXTRA_ARGS=--node-ip=$local_ip
EOF
  echo -e "${GREEN}[SUCCESS] Kubelet configured successfully with IP: $local_ip${NC}"
fi



echo
### installed versions
echo -e "${GREEN}[INFO] installed versions...${NC}"
kubeadm version
kubectl version --client
kubelet --version
containerd --version

echo
### containerd
echo -e "${GREEN}[INFO] configure containerd...${NC}"
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sudo sysctl --system
sudo mkdir -p /etc/containerd

echo


### start services
echo -e "${GREEN}[INFO] start services...${NC}"
sudo systemctl daemon-reload
sudo systemctl enable containerd
sudo systemctl restart containerd
sudo systemctl enable kubelet && systemctl start kubelet


### init k8s
echo -e "${GREEN}[INFO] initialize kubernetes...${NC}"
sudo rm /root/.kube/config || true
# 192.168.81.2 is the IP address of the master node
echo -e "${GREEN}[INFO] 192.168.81.2 is the IP address of the master node...${NC}"

#sudo kubeadm init \
#  --kubernetes-version=v1.30.10 \
#  --control-plane-endpoint=master-node \
#  --ignore-preflight-errors=NumCPU \
#  --skip-token-print \
#  --upload-certs \
#  --pod-network-cidr=192.168.0.0/16 \
#  --apiserver-advertise-address=192.168.81.2 \
#  --apiserver-cert-extra-sans=192.168.81.2 \
#  --apiserver-cert-extra-sans=master-node \
#  --cri-socket=unix:///run/containerd/containerd.sock
#
#mkdir -p ~/.kube
#sudo cp -i /etc/kubernetes/admin.conf ~/.kube/config
#sudo chown $(id -u):$(id -g) ~/.kube/config

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
CNI_VER=3.28.0
echo -e "${GREEN}[INFO] install calico network plugin...${NC}"
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v${CNI_VER}/manifests/tigera-operator.yaml

wget https://raw.githubusercontent.com/projectcalico/calico/v${CNI_VER}/manifests/custom-resources.yaml

kubectl create -f custom-resources.yaml


echo
echo "### COMMAND TO ADD A WORKER NODE ###"
echo
echo -e "${GREEN}[INFO] create join command...${NC}"
kubeadm token create --print-join-command --ttl 0