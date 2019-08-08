#!/usr/bin/env bash
#b8_yang@163.com
#. /etc/profile
bash_path=$(cd "$(dirname "$0")";pwd)
source $bash_path/base.config

if [[ "$(whoami)" != "root" ]]; then
	echo "please run this script as root ." >&2
	exit 1
fi

#log="$bash_path/setup.log"  #操作日志存放路径
#fsize=2000000
#exec 2>>$log  #如果执行过程中有错误信息均输出到日志文件中

echo -e "\033[31m 这个是服务器互信脚本！欢迎关注我的个人公众号“devops的那些事”获得更多实用工具！Please continue to enter or ctrl+C to cancel \033[0m"
#sleep 5
#yum update
yum_update(){
	yum update -y
}
#configure yum source
yum_config(){
  yum install wget epel-release -y
  if [[ $aliyun == "1" ]];then
  test -d /etc/yum.repos.d/bak/ || yum install wget epel-release -y && cd /etc/yum.repos.d/ && mkdir bak && mv -f *.repo bak/ && wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo && wget -O /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-7.repo && yum clean all && yum makecache
  fi
}

yum_init(){
while true ; do
yum -y install iotop iftop yum-utils net-tools git lrzsz expect gcc gcc-c++ make cmake libxml2-devel openssl-devel curl curl-devel unzip sudo ntp libaio-devel wget vim ncurses-devel autoconf automake zlib-devel  python-devel bash-completion
if [[ $? == 0 ]] ; then
echo The command execute OK!
break;
else
echo ERROR : The command execute fialed! 
fi
done
}
#firewalld
iptables_config(){
  systemctl stop firewalld.service
  systemctl disable firewalld.service
#  iptables -P FORWARD ACCEPT
}
#system config
system_config(){
  sed -i "s/SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config
  setenforce 0
  timedatectl set-local-rtc 1 && timedatectl set-timezone Asia/Shanghai
  yum -y install chrony && systemctl start chronyd.service && systemctl enable chronyd.service
  systemctl restart chronyd.service
}


ulimit_config(){
grep 'ulimit' /etc/rc.local
if [[ $? -eq 0 ]];then
echo "内核参数调整完毕！！！"
else
  echo "ulimit -SHn 102400" >> /etc/rc.local
  cat >> /etc/security/limits.conf << EOF
  *           soft   nofile       102400
  *           hard   nofile       102400
  *           soft   nproc        102400
  *           hard   nproc        102400
  *           soft  memlock      unlimited 
  *           hard  memlock      unlimited
EOF
  cat >> /etc/sysctl.conf << EOF
    kernel.pid_max=4194303
EOF
sysctl -p
echo "内核参数调整完毕！！！"
fi
}

ssh_config(){
grep 'UserKnownHostsFile' /etc/ssh/ssh_config
if [[ $? -eq 0 ]];then
echo "ssh参数配置完毕！！！"
else
sed -i "2i StrictHostKeyChecking no\nUserKnownHostsFile /dev/null" /etc/ssh/ssh_config
echo "ssh参数配置完毕！！！"
fi
}



get_localip(){
ipaddr=$(ip addr | awk '/^[0-9]+: / {}; /inet.*global/ {print gensub(/(.*)\/(.*)/, "\\1", "g", $2)}' | grep $ip_segment)
echo "$ipaddr"
}


change_hosts(){
cd $bash_path
num=0
for host in ${hostip[@]}
do
let num+=1
if [[ $host == `get_localip` ]];then
`hostnamectl set-hostname $hostname$num`
grep "$host" /etc/hosts || echo $host `hostname` >> /etc/hosts
else
grep "$host" /etc/hosts || echo $host $hostname$num >> /etc/hosts
fi
done
}


rootssh_trust(){
cd $bash_path
num=0
for host in ${hostip[@]}
do
let num+=1
if [[ `get_localip` != $host ]];then

if [[ ! -f /root/.ssh/id_rsa.pub ]];then
echo '###########init'
expect ssh_trust_init.exp $root_passwd $host
else
echo '###########add'
expect ssh_trust_add.exp $root_passwd $host
fi
scp base.config hwclock_ntp.sh mutual_trust_node.sh ssh_trust_init.exp ssh_trust_add.exp root@$host:/root && scp /etc/hosts root@$host:/etc/hosts && ssh root@$host "hostnamectl set-hostname $hostname$num" && ssh root@$host /root/hwclock_ntp.sh && ssh root@$host /root/mutual_trust_node.sh && ssh root@$host "rm -rf base.config hwclock_ntp.sh mutual_trust_node.sh ssh_trust_init.exp ssh_trust_add.exp" && ssh root@$host "rm -rf base.config hwclock_ntp.sh mutual_trust_node.sh ssh_trust_init.exp ssh_trust_add.exp"

fi
done
}

main(){
 #yum_update
  yum_config
  yum_init
  ssh_config
  iptables_config
  system_config
#  ulimit_config
  change_hosts
  rootssh_trust
}
main 2>&1

