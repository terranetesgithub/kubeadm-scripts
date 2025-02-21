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
KUBE_VERSION=1.31.4

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
  exit 1
fi

echo

echo -e "${GREEN}[INFO] setup vimrc, bashrc, and terminal...${NC}"
### setup terminal
apt-get --allow-unauthenticated update
apt-get --allow-unauthenticated install -y bash-completion binutils
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

echo -e "${GREEN}[INFO] disable linux swap and remove any existing swap partitions...${NC}"
### disable linux swap and remove any existing swap partitions
sudo swapoff -a
sudo sed -i '/\sswap\s/ s/^\(.*\)$/#\1/g' /etc/fstab

# Load necessary kernel modules
sudo modprobe overlay
sudo modprobe br_netfilter

# Ensure modules are loaded on boot
sudo tee /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

# Set required sysctl parameters
sudo tee /etc/sysctl.d/kubernetes.conf <<EOT
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOT

# Apply sysctl parameters
sudo sysctl --system

echo

echo -e "${GREEN}[INFO] remove packages on ubuntu 24.04...${NC}"
### remove packages on ubuntu 24.04
sudo kubeadm reset -f || true
sudo crictl rm --force $(sudo crictl ps -a -q) || true
sudo apt-mark unhold kubelet kubeadm kubectl kubernetes-cni || true
sudo apt-get remove -y docker.io containerd kubelet kubeadm kubectl kubernetes-cni || true
sudo apt-get autoremove -y
sudo systemctl daemon-reload

echo

echo -e "${GREEN}[INFO] install podman on ubuntu 24.04...${NC}"
### install podman on ubuntu 24.04
sudo apt update
sudo apt install podman -y
sudo podman --version
sudo systemctl start podman.socket
sudo systemctl restart podman.socket
sudo systemctl status podman.socket

echo
echo -e "${GREEN}[INFO] install kubelet, kubeadm, kubectl...${NC}"
### install kubelet, kubeadm, kubectl
### install packages in ubuntu 24.04

echo
# Install Containerd dependencies
sudo apt update
echo -e "${GREEN}[INFO] install containerd dependencies...${NC}"
sudo apt install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates

echo
# Add Containerd repository
echo -e "${GREEN}[INFO] add containerd repository...${NC}"
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/containerd.gpg
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

echo
# Install Containerd
echo -e "${GREEN}[INFO] install containerd...${NC}"
sudo apt update && sudo apt install containerd.io -y

echo
# Configure Containerd
echo -e "${GREEN}[INFO] configure containerd...${NC}"
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
sudo systemctl restart containerd

echo
# Add Kubernetes repository
echo -e "${GREEN}[INFO] add kubernetes repository...${NC}"
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/k8s.gpg
sudo tee /etc/apt/sources.list.d/k8s.list <<EOT
deb [signed-by=/etc/apt/keyrings/k8s.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /
EOT

echo

# Install Kubernetes components
echo -e "${GREEN}[INFO] install kubernetes components...${NC}"
sudo apt update
sudo apt install kubelet kubeadm kubectl -y
sudo apt-mark hold kubelet kubeadm kubectl

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
systemctl daemon-reload
systemctl enable containerd
systemctl restart containerd
systemctl enable kubelet && systemctl start kubelet


### init k8s
echo -e "${GREEN}[INFO] initialize kubernetes...${NC}"
rm /root/.kube/config || true
kubeadm init --kubernetes-version=1.31.4 --control-plane-endpoint=master-node --ignore-preflight-errors=NumCPU --skip-token-print --pod-network-cidr 192.168.0.0/16

#  --apiserver-advertise-address=192.168.79.2 \

#kubeadm init \
#  --kubernetes-version=1.31.4 \
#  --control-plane-endpoint=master-node \
#  --ignore-preflight-errors=NumCPU \
#  --skip-token-print \
#  --pod-network-cidr 192.168.0.0/16

mkdir -p ~/.kube
sudo cp -i /etc/kubernetes/admin.conf ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config


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