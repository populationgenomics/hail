#!/bin/bash

set -ex

curl --silent --show-error --remote-name --fail https://dl.google.com/cloudagents/add-logging-agent-repo.sh
bash add-logging-agent-repo.sh


# Get the latest GPG key as it might not always be up to date
# https://cloud.google.com/compute/docs/troubleshooting/known-issues#keyexpired
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
apt-get update

# Avoid any prompts from apt install.
export DEBIAN_FRONTEND=noninteractive

apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    google-fluentd \
    google-fluentd-catch-all-config-structured \
    gnupg \
    jq \
    software-properties-common \
    wget

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -

add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

# Install NVIDIA GPU drivers and NVIDIA Container Toolkit. This needs to happen before
# the Docker daemon configuration is updated, to avoid conflicts.
# https://docs.nvidia.com/cuda/cuda-installation-guide-linux/#ubuntu-installation-network
# https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html#docker
DISTRIBUTION=$(. /etc/os-release;echo $ID$VERSION_ID)
apt-key del 7fa2af80  # Remove deprecated NVIDIA key.
wget https://developer.download.nvidia.com/compute/cuda/repos/${DISTRIBUTION/\./}/x86_64/cuda-keyring_1.0-1_all.deb
dpkg -i cuda-keyring_1.0-1_all.deb && rm cuda-keyring_1.0-1_all.deb
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/$DISTRIBUTION/libnvidia-container.list | \
            sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
            tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt update && apt install -y cuda docker-ce nvidia-docker2

# https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html#step-3-rootless-containers-setup
sed -i 's/^#no-cgroups = false/no-cgroups = true/;' /etc/nvidia-container-runtime/config.toml

rm -rf /var/lib/apt/lists/*

[ -f /etc/docker/daemon.json ] || echo "{}" > /etc/docker/daemon.json

VERSION=2.0.4
OS=linux
ARCH=amd64

curl -fsSL "https://github.com/GoogleCloudPlatform/docker-credential-gcr/releases/download/v${VERSION}/docker-credential-gcr_${OS}_${ARCH}-${VERSION}.tar.gz" \
  | tar xz --to-stdout ./docker-credential-gcr \
	> /usr/bin/docker-credential-gcr && chmod +x /usr/bin/docker-credential-gcr

# avoid "unable to get current user home directory: os/user lookup failed"
export HOME=/root

docker-credential-gcr configure-docker --include-artifact-registry
docker pull {{ global.docker_root_image }}

# add docker daemon debug logging
jq '.debug = true' /etc/docker/daemon.json > daemon.json.tmp
mv daemon.json.tmp /etc/docker/daemon.json

shutdown -h now
