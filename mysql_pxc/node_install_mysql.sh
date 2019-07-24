#!/bin/bash
#b8_yang@163.com
bash_path=$(cd "$(dirname "$0")";pwd)
source ./base.config


if [[ "$(whoami)" != "root" ]]; then
	echo "please run this script as root ." >&2
	exit 1
fi

log="./setup.log"  #操作日志存放路径 
fsize=2000000         
exec 2>>$log  #如果执行过程中有错误信息均输出到日志文件中

echo -e "\033[31m 这个是mysql集群一键部署脚本！欢迎关注我的个人公众号“devops的那些事”获得更多实用工具Please continue to enter or ctrl+C to cancel \033[0m"

#yum update
yum_update(){
	yum update -y
}
#configure yum source
yum_config(){
  yum clean all && yum makecache
  yum install wget epel-release -y
  yum -y install iotop iftop yum-utils nc net-tools git lrzsz expect gcc gcc-c++ make cmake libxml2-devel openssl-devel curl curl-devel unzip sudo ntp libaio-devel wget vim ncurses-devel autoconf automake zlib-devel  python-devel bash-completion
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
  #yum -y install chrony && systemctl start chronyd.service && systemctl enable chronyd.service
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

config_docker(){


sed -i "/^ExecStart/cExecStart=\/usr\/bin\/dockerd -H tcp:\/\/0\.0\.0\.0:2375 -H unix:\/\/\/var\/run\/docker.sock" /usr/lib/systemd/system/docker.service
systemctl daemon-reload
systemctl restart docker.service

}

setupkernel(){
 rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
 rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm
 yum --enablerepo=elrepo-kernel install -y kernel-lt kernel-lt-devel
 grub2-set-default 0
}

deploy_keepalived(){
cd $bash_path
yum install keepalived -y
sed -i "s/keepalived_vip/$keepalived_vip/g" ./keepalived.conf
sed -i "s/interface eth0/interface $interface/g" ./keepalived.conf
mv /etc/keepalived/keepalived.conf /etc/keepalived/keepalived.conf.bak
cp keepalived.conf chk_mysql.sh /etc/keepalived/
chmod 644 /etc/keepalived/keepalived.conf

}

change_hosts(){
num=0
cd $bash_path
for host in ${hostip[@]}
do
let num+=1
if [[ $host == `get_localip` ]];then
`hostnamectl set-hostname $hostname$num`

fi
done

rm -rf $database_path/mysql/
mkdir -p $database_path/mysql/{data,backup}
chmod -R 777 $database_path/mysql/

}


#ssh trust
rootssh_trust(){

for host in ${hostip[@]}
do
if [[ `get_localip` != $host ]];then

if [[ ! -f "/root/.ssh/id_rsa.pub" ]];then
expect ssh_trust_init.exp $root_passwd $host
else
expect ssh_trust_add.exp $root_passwd $host
echo "remote machine root user succeed!!!!!!!!!!!!!!!! "
fi

fi
done

}


#install docker
install_docker() {
mkdir -p /etc/docker
yum-config-manager --add-repo  https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
yum install -y --setopt=obsoletes=0 docker-ce-18.09.4-3.el7
tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": ["https://gpkhi0nk.mirror.aliyuncs.com"]
}
EOF
systemctl daemon-reload
systemctl enable docker
systemctl restart docker
}



main(){
 #yum_update
 #setupkernel
 yum_config
 ssh_config
 iptables_config
 system_config
 ulimit_config
 #sysctl_config
 deploy_keepalived
 install_docker
 config_docker
 
 
 change_hosts
 rootssh_trust

}
main > ./setup.log 2>&1
