yum install -y curl wget
if [ ! -f /usr/local/bin/cfssl ]; then
  curl -L https://pkg.cfssl.org/R1.2/cfssl_linux-amd64 -o /usr/local/bin/cfssl
  chmod +x /usr/local/bin/cfssl
fi

if [ ! -f /usr/local/bin/cfssljson ]; then
  curl -L https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64 -o /usr/local/bin/cfssljson
  chmod +x /usr/local/bin/cfssljson
fi

if [ ! -f /usr/local/bin/cfssl-certinfo ]; then
  curl -L https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64 -o /usr/local/bin/cfssl-certinfo
  chmod +x /usr/local/bin/cfssl-certinfo
fi

echo 'export PATH=$PATH:/usr/local/bin:/usr/bin' >> ~/.bashrc
source ~/.bashrc

mkdir -p /opt/k8s/work
cd /opt/k8s/work
cat > ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "87600h"
    },
    "profiles": {
      "kubernetes": {
        "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ],
        "expiry": "87600h"
      }
    }
  }
}
EOF
cat > ca-csr.json <<EOF
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "4Paradigm"
    }
  ]
}
EOF
cfssl gencert -initca ca-csr.json | cfssljson -bare ca
chmod +r ./*.pem

## Please refer to: https://github.com/opsnull/follow-me-install-kubernetes-cluster/blob/master/03.%E9%83%A8%E7%BD%B2kubectl%E5%91%BD%E4%BB%A4%E8%A1%8C%E5%B7%A5%E5%85%B7.md
## setup kubectl and kube-config
cat > admin-csr.json <<EOF
{
  "CN": "admin",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "system:masters",
      "OU": "4Paradigm"
    }
  ]
}
EOF
cfssl gencert -ca=/opt/k8s/work/ca.pem \
  -ca-key=/opt/k8s/work/ca-key.pem \
  -config=/opt/k8s/work/ca-config.json \
  -profile=kubernetes admin-csr.json | cfssljson -bare admin

if [ -f ./kubernetes-client-linux-amd64.tar.gz ]; then
  echo 'Remove old file kubernetes-client-linux-amd64.tar.gz'
  sudo rm ./kubernetes-client-linux-amd64.tar.gz
fi

if [ -d ./kubernetes ]; then
  echo "remove directory: ./kubernetes"
  sudo rm -r ./kubernetes
fi

curl -L https://dl.k8s.io/v1.14.0/kubernetes-client-linux-amd64.tar.gz -o kubernetes-client-linux-amd64.tar.gz
tar -xzvf kubernetes-client-linux-amd64.tar.gz

mkdir -p /opt/k8s/bin
if [ -f /opt/k8s/bin/kubectl ]; then
  echo 'Remove file /opt/k8s/bin/kubectl'
  sudo rm /opt/k8s/bin/kubectl
fi
sudo cp ./kubernetes/client/bin/kubectl /opt/k8s/bin/kubectl
chmod 777 /opt/k8s/bin/kubectl
echo 'export PATH=$PATH:/opt/k8s/bin' >> ~/.bashrc
source ~/.bashrc

if [ -f ./kubectl.kubeconfig ]; then
  echo 'Remove old file ./kubectl.kubeconfig'
  sudo rm ./kubectl.kubeconfig
fi

# 设置集群参数
kubectl config set-cluster kubernetes \
  --certificate-authority=/opt/k8s/work/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=kubectl.kubeconfig

# 设置客户端认证参数
kubectl config set-credentials admin \
  --client-certificate=/opt/k8s/work/admin.pem \
  --client-key=/opt/k8s/work/admin-key.pem \
  --embed-certs=true \
  --kubeconfig=kubectl.kubeconfig

# 设置上下文参数
kubectl config set-context kubernetes \
  --cluster=kubernetes \
  --user=admin \
  --kubeconfig=kubectl.kubeconfig
  
# 设置默认上下文
kubectl config use-context kubernetes --kubeconfig=kubectl.kubeconfig
chmod +r ./kubectl.kubeconfig

## download etcd
## https://github.com/opsnull/follow-me-install-kubernetes-cluster/blob/master/04.%E9%83%A8%E7%BD%B2etcd%E9%9B%86%E7%BE%A4.md
if [ -f ./etcd-v3.3.13-linux-amd64.tar.gz ]; then
  sudo rm ./etcd-v3.3.13-linux-amd64.tar.gz
fi

wget https://github.com/etcd-io/etcd/releases/download/v3.3.13/etcd-v3.3.13-linux-amd64.tar.gz

if [ -d "./etcd-v3.3.13-linux-amd64" ]; then
  sudo rm -r etcd-v3.3.13-linux-amd64
fi
tar -zxf ./etcd-v3.3.13-linux-amd64.tar.gz

# 创建 etcd 证书和私钥
cd /opt/k8s/work
cat > etcd-csr.json <<EOF
{
  "CN": "etcd",
  "hosts": [
    "127.0.0.1",
    "172.27.128.150",
    "172.27.128.149",
    "172.27.128.148"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "4Paradigm"
    }
  ]
}
EOF
cfssl gencert -ca=/opt/k8s/work/ca.pem \
    -ca-key=/opt/k8s/work/ca-key.pem \
    -config=/opt/k8s/work/ca-config.json \
    -profile=kubernetes etcd-csr.json | cfssljson -bare etcd
cat > etcd.service.template <<EOF
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target
Documentation=https://github.com/coreos

[Service]
Type=notify
WorkingDirectory=${ETCD_DATA_DIR}
ExecStart=/opt/k8s/bin/etcd \\
  --data-dir=${ETCD_DATA_DIR} \\
  --wal-dir=${ETCD_WAL_DIR} \\
  --name=##NODE_NAME## \\
  --cert-file=/etc/etcd/cert/etcd.pem \\
  --key-file=/etc/etcd/cert/etcd-key.pem \\
  --trusted-ca-file=/etc/kubernetes/cert/ca.pem \\
  --peer-cert-file=/etc/etcd/cert/etcd.pem \\
  --peer-key-file=/etc/etcd/cert/etcd-key.pem \\
  --peer-trusted-ca-file=/etc/kubernetes/cert/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --listen-peer-urls=https://##NODE_IP##:2380 \\
  --initial-advertise-peer-urls=https://##NODE_IP##:2380 \\
  --listen-client-urls=https://##NODE_IP##:2379,http://127.0.0.1:2379 \\
  --advertise-client-urls=https://##NODE_IP##:2379 \\
  --initial-cluster-token=etcd-cluster-0 \\
  --initial-cluster=${ETCD_NODES} \\
  --initial-cluster-state=new \\
  --auto-compaction-mode=periodic \\
  --auto-compaction-retention=1 \\
  --max-request-bytes=33554432 \\
  --quota-backend-bytes=6442450944 \\
  --heartbeat-interval=250 \\
  --election-timeout=2000
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
source /opt/k8s/bin/environment.sh
for (( i=0; i < 3; i++ ))
  do
    sed -e "s/##NODE_NAME##/${NODE_NAMES[i]}/" -e "s/##NODE_IP##/${NODE_IPS[i]}/" etcd.service.template > etcd-${NODE_IPS[i]}.service 
  done




















