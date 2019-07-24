#!/bin/bash
#b8_yang@163.com
source ./base.config
bash_path=$(cd "$(dirname "$0")";pwd)

if [[ "$(whoami)" != "root" ]]; then
	echo "please run this script as root ." >&2
	exit 1
fi

log="./setup.log"  #操作日志存放路径 
fsize=2000000         
exec 2>>$log  #如果执行过程中有错误信息均输出到日志文件中

echo -e "\033[31m 这个是k8sV1.13.1集群一键部署脚本！欢迎关注我的个人公众号“devops的那些事”获得更多实用工具！Please continue to enter or ctrl+C to cancel \033[0m"
sleep 5
#yum update
yum_update(){
	yum update -y
}
#configure yum source
yum_config(){
  yum install wget epel-release -y
  cd /etc/yum.repos.d/ && mkdir bak && mv -f *.repo bak/
  wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo
  wget -O /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-7.repo
  yum clean all && yum makecache
  yum -y install iotop iftop yum-utils net-tools git lrzsz expect gcc gcc-c++ make cmake libxml2-devel openssl-devel curl curl-devel unzip sudo ntp libaio-devel wget vim ncurses-devel autoconf automake zlib-devel  python-devel bash-completion
  ntpdate 0.asia.pool.ntp.org
}
#firewalld
iptables_config(){
  systemctl stop firewalld.service
  systemctl disable firewalld.service

  iptables -P FORWARD ACCEPT
}
#system config
system_config(){
  sed -i "s/SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config
  timedatectl set-local-rtc 1 && timedatectl set-timezone Asia/Shanghai
  yum -y install chrony && systemctl start chronyd.service && systemctl enable chronyd.service
}
ulimit_config(){
  echo "ulimit -SHn 102400" >> /etc/rc.local
  cat >> /etc/security/limits.conf << EOF
  *           soft   nofile       102400
  *           hard   nofile       102400
  *           soft   nproc        102400
  *           hard   nproc        102400
  *           soft  memlock      unlimited 
  *           hard  memlock      unlimited
EOF

}

ssh_config(){

if [`grep 'UserKnownHostsFile' /etc/ssh/ssh_config`];then
echo "pass"
else
sed -i "2i StrictHostKeyChecking no\nUserKnownHostsFile /dev/null" /etc/ssh/ssh_config
fi
}

#set sysctl
sysctl_config(){
  cp /etc/sysctl.conf /etc/sysctl.conf.bak
  cat > /etc/sysctl.conf << EOF
  #docker
  net.bridge.bridge-nf-call-iptables = 1
  net.bridge.bridge-nf-call-ip6tables = 1
EOF
  /sbin/sysctl -p
  echo "sysctl set OK!!"
}

#swapoff
swapoff(){
  /sbin/swapoff -a
  sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
  echo "vm.swappiness=0" >> /etc/sysctl.conf
  /sbin/sysctl -p
}

get_localip(){

ipaddr=$(ip addr | awk '/^[0-9]+: / {}; /inet.*global/ {print gensub(/(.*)\/(.*)/, "\\1", "g", $2)}' | grep $ip_segment)
echo "$ipaddr"
}

setupkernel(){
 rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
 rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm
 yum --enablerepo=elrepo-kernel install -y kernel-lt kernel-lt-devel
 grub2-set-default 0
}

change_hosts(){
num=0
cd $bash_path
rm -rf ./new_hostname_list.config
touch ./new_hostname_list.config
for host in $hostip
do
let num+=1
if [ $host = `get_localip` ];then
`hostnamectl set-hostname $hostname$num`
echo $host `hostname` >> /etc/hosts
echo `hostname` >> ./new_hostname_list.config
else
echo $host $hostname$num >> /etc/hosts
echo $hostname$num >> ./new_hostname_list.config
fi
done
}


rootssh_trust(){
cd $bash_path
for host in `cat ./new_hostname_list.config`
do
if [ `hostname` != $host ];then
#ls /root/.ssh/id_rsa.pub
if [ ! -f "/root/.ssh/id_rsa.pub" ];then
echo '###########init'
expect ssh_trust_init.exp $root_passwd $host
else
echo '###########add'
expect ssh_trust_add.exp $root_passwd $host
fi
echo "$host  install k8s please wait!!!!!!!!!!!!!!! "
scp base.config node_install_k8s.sh new_hostname_list.config ssh_trust_init.exp ssh_trust_add.exp root@$host:/root && scp /etc/hosts root@$host:/etc/hosts && ssh root@$host /root/node_install_k8s.sh

echo "$host install k8s success!!!!!!!!!!!!!!! "
fi
done
}

ca_hash(){
cd $bash_path
hash_value=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')
echo $hash_value
}

#install docker
install_docker() {
cd $bash_path
yum-config-manager --add-repo  https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
yum install -y --setopt=obsoletes=0 docker-ce-18.06.1.ce-3.el7
systemctl start docker
systemctl enable docker
}

set_repo(){
cd $bash_path
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
	yum -y install kubelet-1.13.1 kubeadm-1.13.1 kubectl-1.13.1 kubernetes-cni-0.6.0
	yum list installed | grep kube
	systemctl daemon-reload
	systemctl enable kubelet
	systemctl start kubelet
}

install_masterk8s(){
	images=(kube-scheduler:v1.13.1
			kube-proxy:v1.13.1
			kube-controller-manager:v1.13.1
			kube-apiserver:v1.13.1
			pause:3.1
			coredns:1.2.6
			etcd:3.2.24)
	for imagename in ${images[@]}; do
	docker pull mathlsj/$imagename
	docker tag mathlsj/$imagename k8s.gcr.io/$imagename
	docker rmi mathlsj/$imagename
	done

	docker pull quay.io/coreos/flannel:v0.10.0-amd64
}
init_k8s(){
cd $bash_path
	set -e
	rm -rf /root/.kube
	kubeadm reset -f
	
	kubeadm init --kubernetes-version=$k8s_version --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=$masterip
	
	mkdir -p /root/.kube
	cp /etc/kubernetes/admin.conf /root/.kube/config
	chown $(id -u):$(id -g) /root/.kube/config
	cp -p /root/.bash_profile /root/.bash_profile.bak$(date '+%Y%m%d%H%M%S')
	echo "export KUBECONFIG=/root/.kube/config" >> /root/.bash_profile
	source /root/.bash_profile
}

token_shar_value(){
cd $bash_path
/usr/bin/kubeadm token list > token_shar_value.text
echo tocken=$(sed -n "2, 1p" token_shar_value.text | awk '{print $1}') >> base.config
openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //' > token_shar_value.text
echo "sha_value=$(cat token_shar_value.text)"  >> base.config
rm -rf token_shar_value.text

}

install_flannel(){
	wget https://raw.githubusercontent.com/coreos/flannel/bc79dd1505b0c8681ece4de4c0d86c5cd2643275/Documentation/kube-flannel.yml
	kubectl apply -f kube-flannel.yml
}


main(){
 #yum_update
  #setupkernel
  yum_config
  ssh_config
  iptables_config
  system_config
  ulimit_config
  sysctl_config
  change_hosts
  swapoff
  install_docker
  set_repo
  install_masterk8s
  init_k8s
  install_flannel
  token_shar_value
 
 rootssh_trust
}
main > ./setup.log 2>&1