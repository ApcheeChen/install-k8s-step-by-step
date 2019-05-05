#!/bin/bash

# add user 'docker'
useradd -m docker
echo 'export PATH=$PATH:/usr/bin:/usr/local/bin' >> /root/.bashrc
echo 'export PATH=$PATH:/opt/k8s/bin' >> /root/.bashrc

# create relative directories
mkdir -p  /opt/k8s/{bin,work} /etc/kubernetes/cert /etc/etcd/cert
mkdir -p ~/.kube

# install dependencies
yum install -y epel-release
yum install -y conntrack ipvsadm ipset jq iptables curl sysstat libseccomp
/usr/sbin/modprobe ip_vs

# close and disable firewall
systemctl stop firewalld
systemctl disable firewalld
iptables -F && iptables -X && iptables -F -t nat && iptables -X -t nat
iptables -P FORWARD ACCEPT

# close swap
wapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# close SELinux
setenforce 0
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config

# reload kernel modules
modprobe br_netfilter

# optmize kernel arguments
cat > kubernetes.conf <<EOF
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
net.ipv4.tcp_tw_recycle=0
vm.swappiness=0 # 禁止使用 swap 空间，只有当系统 OOM 时才允许使用它
vm.overcommit_memory=1 # 不检查物理内存是否够用
vm.panic_on_oom=0 # 开启 OOM
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=1048576
fs.file-max=52706963
fs.nr_open=52706963
net.ipv6.conf.all.disable_ipv6=1
net.netfilter.nf_conntrack_max=2310720
EOF
cp kubernetes.conf  /etc/sysctl.d/kubernetes.conf
sysctl -p /etc/sysctl.d/kubernetes.conf

# setup timezone
# 调整系统 TimeZone
timedatectl set-timezone Asia/Shanghai

# 将当前的 UTC 时间写入硬件时钟
timedatectl set-local-rtc 0

# 重启依赖于系统时间的服务
systemctl restart rsyslog 
systemctl restart crond

# update system time
ntpdate cn.pool.ntp.org

# close un relative services
systemctl stop postfix && systemctl disable postfix


# setup rsyslogd and systemd journald
mkdir /var/log/journal # 持久化保存日志的目录
mkdir /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-prophet.conf <<EOF
[Journal]
# 持久化保存到磁盘
Storage=persistent

# 压缩历史日志
Compress=yes

SyncIntervalSec=5m
RateLimitInterval=30s
RateLimitBurst=1000

# 最大占用空间 10G
SystemMaxUse=10G

# 单日志文件最大 200M
SystemMaxFileSize=200M

# 日志保存时间 2 周
MaxRetentionSec=2week

# 不将日志转发到 syslog
ForwardToSyslog=no
EOF
systemctl restart systemd-journald


