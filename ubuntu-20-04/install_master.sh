#!/bin/sh

# Source: http://kubernetes.io/docs/getting-started-guides/kubeadm

set -e

# Color codes
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}[INFO] Verify ubuntu release...${NC}"
source /etc/lsb-release
if [ "$DISTRIB_RELEASE" != "20.04" ]; then
    echo "################################# "
    echo "############ WARNING ############ "
    echo "################################# "
    echo
    echo "This script only works on Ubuntu 20.04!"
    echo "You're using: ${DISTRIB_DESCRIPTION}"
    echo "Better ABORT with Ctrl+C. Or press any key to continue the install"
    read
fi

echo

KUBE_VERSION=1.31.1

# get platform
PLATFORM=`uname -p`

echo -e "${GREEN}[INFO] Verify platform...${NC}"

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

echo -e "${GREEN}[INFO] Setup vimrc, bashrc, and terminal...${NC}"

echo
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

echo -e "${GREEN}disable linux swap and remove any existing swap partitions...${NC}"
swapoff -a
sed -i '/\sswap\s/ s/^\(.*\)$/#\1/g' /etc/fstab

echo

echo -e "${GREEN}[INFO] Remove packages...${NC}"
### remove packages
kubeadm reset -f || true
crictl rm --force $(crictl ps -a -q) || true
apt-mark unhold kubelet kubeadm kubectl kubernetes-cni || true
apt-get remove -y docker.io containerd kubelet kubeadm kubectl kubernetes-cni || true
apt-get autoremove -y
systemctl daemon-reload

echo

echo -e "${GREEN}[INFO] Install podman...${NC}"
### install podman
. /etc/os-release
echo "deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${VERSION_ID}/ /" | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:testing.list
curl -L "http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${VERSION_ID}/Release.key" | sudo apt-key add -
apt-get update -qq
apt-get -qq -y install podman cri-tools containers-common
rm /etc/apt/sources.list.d/devel:kubic:libcontainers:testing.list
cat <<EOF | sudo tee /etc/containers/registries.conf
[registries.search]
registries = ['docker.io']
EOF

echo
echo -e "${GREEN}[INFO] Install kubelet, kubeadm, and kubectl...${NC}"
### install kubelet, kubeadm, and kubectl

### install packages
apt-get install -y apt-transport-https ca-certificates
mkdir -p /etc/apt/keyrings
rm /etc/apt/keyrings/kubernetes-1-31-apt-keyring.gpg || true
rm /etc/apt/keyrings/kubernetes-1-30-apt-keyring.gpg || true
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-1-31-apt-keyring.gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-1-30-apt-keyring.gpg
echo > /etc/apt/sources.list.d/kubernetes.list
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-1-31-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-1-30-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
apt-get --allow-unauthenticated update
apt-get --allow-unauthenticated install -y docker.io containerd kubelet=${KUBE_VERSION}-1.1 kubeadm=${KUBE_VERSION}-1.1 kubectl=${KUBE_VERSION}-1.1 kubernetes-cni
apt-mark hold kubelet kubeadm kubectl kubernetes-cni

echo

echo -e "${GREEN}[INFO] Install containerd...${NC}"
# Download and install containerd
### install containerd 1.6 over apt-installed-version
wget https://github.com/containerd/containerd/releases/download/v1.6.12/containerd-1.6.12-linux-${PLATFORM}.tar.gz
tar xvf containerd-1.6.12-linux-${PLATFORM}.tar.gz
systemctl stop containerd
mv bin/* /usr/bin
rm -rf bin containerd-1.6.12-linux-${PLATFORM}.tar.gz
systemctl unmask containerd
systemctl start containerd

echo

echo -e "${GREEN}[INFO] Configure containerd...${NC}"
### containerd
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
echo -e "${GREEN}[INFO] Initialize kubeadm...${NC}"
### initialize kubeadm
### containerd config
cat > /etc/containerd/config.toml <<EOF
disabled_plugins = []
imports = []
oom_score = 0
plugin_dir = ""
required_plugins = []
root = "/var/lib/containerd"
state = "/run/containerd"
version = 2

[plugins]

  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
      base_runtime_spec = ""
      container_annotations = []
      pod_annotations = []
      privileged_without_host_devices = false
      runtime_engine = ""
      runtime_root = ""
      runtime_type = "io.containerd.runc.v2"

      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
        BinaryName = ""
        CriuImagePath = ""
        CriuPath = ""
        CriuWorkPath = ""
        IoGid = 0
        IoUid = 0
        NoNewKeyring = false
        NoPivotRoot = false
        Root = ""
        ShimCgroup = ""
        SystemdCgroup = true
EOF

echo
echo -e "${GREEN}[INFO] Configure crictl...${NC}"
### crictl uses containerd as default
{
cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
EOF
}

echo
echo -e "${GREEN}[INFO] Configure kubelet...${NC}"
### kubelet should use containerd
{
cat <<EOF | sudo tee /etc/default/kubelet
KUBELET_EXTRA_ARGS="--container-runtime-endpoint unix:///run/containerd/containerd.sock"
EOF
}

echo
echo -e "${GREEN}[INFO] Start services...${NC}"

### start services
systemctl daemon-reload
systemctl enable containerd
systemctl restart containerd
systemctl enable kubelet && systemctl start kubelet

echo
echo -e "${GREEN}[INFO] Join the cluster...${NC}"
### init k8s
rm /root/.kube/config || true
kubeadm init --kubernetes-version=${KUBE_VERSION} --ignore-preflight-errors=NumCPU --skip-token-print --pod-network-cidr 192.168.0.0/16

mkdir -p ~/.kube
sudo cp -i /etc/kubernetes/admin.conf ~/.kube/config

echo
echo -e "${GREEN}[INFO] Install CNI...${NC}"
### CNI

## Download the Calico networking manifest for the Kubernetes API datastore
#curl https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/calico.yaml -O
echo
echo -e "${GREEN}[INFO] Deploying Calico...${NC}"
kubectl apply -f calico.yaml

echo
echo -e "${GREEN}[INFO] Install etcdctl...${NC}"
# etcdctl
ETCDCTL_VERSION=v3.5.1
ETCDCTL_ARCH=$(dpkg --print-architecture)
ETCDCTL_VERSION_FULL=etcd-${ETCDCTL_VERSION}-linux-${ETCDCTL_ARCH}
wget https://github.com/etcd-io/etcd/releases/download/${ETCDCTL_VERSION}/${ETCDCTL_VERSION_FULL}.tar.gz
tar xzf ${ETCDCTL_VERSION_FULL}.tar.gz ${ETCDCTL_VERSION_FULL}/etcdctl
mv ${ETCDCTL_VERSION_FULL}/etcdctl /usr/bin/
rm -rf ${ETCDCTL_VERSION_FULL} ${ETCDCTL_VERSION_FULL}.tar.gz

echo
echo -e "${GREEN}[INFO] Join the cluster...${NC}"
### join the cluster
echo "### COMMAND TO ADD A WORKER NODE ###"
kubeadm token create --print-join-command --ttl 0


echo
echo -e "${GREEN}[INFO] Deploy debugging pods...${NC}"

# Function to deploy a pod if it doesn't exist
deploy_pod_if_not_exists() {
    local pod_name=$1
    local image=$2
    if ! kubectl get pod $pod_name &> /dev/null; then
        echo "Deploying $pod_name..."
        kubectl run $pod_name --image=$image --restart=Always -- sleep infinity
    else
        echo "$pod_name already exists, skipping deployment."
    fi
}

# Deploy debug pod for network testing
deploy_pod_if_not_exists "debug-pod" "georgeezejiofor/network-test:latest"

# Deploy netshoot debug pod for network testing
deploy_pod_if_not_exists "netshoot-debug" "nicolaka/netshoot:latest"

# Wait for the pods to be ready
echo "Waiting for debug-pod and netshoot-debug to be ready..."
kubectl wait --for=condition=ready pod/debug-pod --timeout=60s || echo "Timeout waiting for debug-pod"
kubectl wait --for=condition=ready pod/netshoot-debug --timeout=60s || echo "Timeout waiting for netshoot-debug"

echo -e "${GREEN}[INFO] Debugging pods deployment completed.${NC}"

echo
echo -e "${GREEN}[INFO] Kubernetes cluster deployed successfully.${NC}"
echo
echo -e "${GREEN}[INFO] Run 'kubectl get nodes' to verify the cluster status.${NC}"
echo
echo -e "${GREEN}[INFO] Run 'kubectl get pods --all-namespaces' to verify the pod status.${NC}"
echo
echo -e "${GREEN}[INFO] Run 'kubectl get svc --all-namespaces' to get the services.${NC}"
echo
