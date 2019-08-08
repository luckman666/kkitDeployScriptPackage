#!/bin/bash
#b8_yang@163.com
bash_path=$(cd "$(dirname "$0")";pwd)
source $bash_path/base.config


if [[ "$(whoami)" != "root" ]]; then
	echo "please run this script as root ." >&2
	exit 1
fi

# log="./setup.log"  #操作日志存放路径 
# fsize=2000000         
# exec 2>>$log  #如果执行过程中有错误信息均输出到日志文件中

echo -e "\033[31m 这个是mysql集群一键部署脚本！欢迎关注我的个人公众号“devops的那些事”获得更多实用工具！！Please continue to enter or ctrl+C to cancel \033[0m"
sleep 5
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
num=0
while true ; do
let num+=1
yum -y install iotop iftop yum-utils net-tools rsync git lrzsz expect gcc gcc-c++ make cmake libxml2-devel openssl-devel curl curl-devel unzip sudo ntp libaio-devel wget vim ncurses-devel autoconf automake zlib-devel  python-devel bash-completion
if [[ $? -eq 0 ]] ; then
echo "初始化安装环境配置完成！！！"
break;
else
if [[ num -gt 3 ]];then
echo "你登录 "$masterip" 瞅瞅咋回事？一直无法yum包"
break
fi
echo "FK!~没成功？哥再来一次！！"
fi
done
}

#firewalld
iptables_config(){
if [[ `ps -ef | grep firewalld |wc -l` -gt 1 ]];then
  systemctl stop firewalld.service
  systemctl disable firewalld.service
  echo "防火墙我关了奥！！！"
fi
#  iptables -P FORWARD ACCEPT
}

#system config
system_config(){
grep "SELINUX=disabled" /etc/selinux/config
if [[ $? -eq 0 ]];then
  echo "SELINUX 已经禁用！！"
else
  sed -i "s/SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config
  setenforce 0
  echo "SELINUX 已经禁用！！"
fi

if [[ `ps -ef | grep chrony |wc -l` -eq 1 ]];then
  timedatectl set-local-rtc 1 && timedatectl set-timezone Asia/Shanghai
  yum -y install chrony && systemctl start chronyd.service && systemctl enable chronyd.service
  systemctl restart chronyd.service
  echo "时钟同步chrony服务安装完毕！！"
fi
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
    vm.swappiness = 0
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

#set sysctl
sysctl_config(){
  cp /etc/sysctl.conf /etc/sysctl.conf.bak
  cat > /etc/sysctl.conf << EOF
  #docker
  net.bridge.bridge-nf-call-iptables = 1
  net.bridge.bridge-nf-call-ip6tables = 1
  vm.swappiness=0
EOF
  /sbin/sysctl -p
  echo "sysctl set OK!!"
}



get_localip(){
ipaddr=$(ip addr | awk '/^[0-9]+: / {}; /inet.*global/ {print gensub(/(.*)\/(.*)/, "\\1", "g", $2)}' | grep $ip_segment)
echo "$ipaddr"
}

deploy_keepalived(){
test -f /etc/keepalived/keepalived.conf 
if [[ $? -eq 0 ]];then
echo "keepalived 部署完毕！！"
else
cd $bash_path
yum install keepalived -y
sed -i "s/keepalived_vip/$keepalived_vip/g" ./keepalived.conf
sed -i "/^interface/c interface $interface" ./keepalived.conf
sed -i "s/outport/$outport/g" ./chk_mysql.sh
#sed -i "s/interface eth0/interface $interface/g" ./keepalived.conf
mv /etc/keepalived/keepalived.conf /etc/keepalived/keepalived.conf.bak
cp keepalived.conf chk_mysql.sh /etc/keepalived/
chmod 644 /etc/keepalived/keepalived.conf
fi
}


change_hosts(){
num=0
cd $bash_path

for host in ${hostip[@]}
do
let num+=1
if [ $host == `get_localip` ];then
`hostnamectl set-hostname $hostname$num`
docker swarm init --advertise-addr $masterip

echo $(docker swarm join-token worker | grep "docker") >> swarm_join_work.sh
`chmod 755 ./swarm_join_work.sh`

docker network create -d  overlay --subnet=$subnet --attachable swarm_mysql_pxc
grep "$host" /etc/hosts || echo $host `hostname` >> /etc/hosts
else
grep "$host" /etc/hosts || echo $host $hostname$num >> /etc/hosts
fi
done
}


rootssh_trust(){
cd $bash_path
for host in ${hostip[@]}
do
if [[ `get_localip` != $host ]];then

if [ ! -f "/root/.ssh/id_rsa.pub" ];then
expect ssh_trust_init.exp $root_passwd $host
else
expect ssh_trust_add.exp $root_passwd $host
fi

echo "$host  install mysql please wait!!!!!!!!!!!!!!! "
scp base.config swarm_join_work.sh hwclock_ntp.sh keepalived.conf chk_mysql.sh node_install_mysql.sh ssh_trust_init.exp ssh_trust_add.exp root@$host:/root && scp /etc/hosts root@$host:/etc/hosts && ssh root@$host "hostnamectl set-hostname $hostname$num" && ssh root@$host /root/hwclock_ntp.sh && ssh root@$host /root/node_install_mysql.sh && ssh root@$host /root/swarm_join_work.sh && ssh root@$host "rm -rf base.config swarm_join_work.sh hwclock_ntp.sh keepalived.conf chk_mysql.sh node_install_mysql.sh ssh_trust_init.exp ssh_trust_add.exp"
echo "$host install mysql  success!!!!!!!!!!!!!!! "

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


config_docker(){
grep "tcp://0.0.0.0:2375" /usr/lib/systemd/system/docker.service
if [[ $? -eq 0 ]];then
echo "docker API接口已经配置完毕"
else
sed -i "/^ExecStart/cExecStart=\/usr\/bin\/dockerd -H tcp:\/\/0\.0\.0\.0:2375 -H unix:\/\/\/var\/run\/docker.sock" /usr/lib/systemd/system/docker.service
systemctl daemon-reload
systemctl restart docker.service
echo "docker API接口已经配置完毕"
fi
}

#swarm_master(){
#docker run --rm swarm create
#echo tocken=`$(docker run --rm swarm create)` >> base.config

#}



deploy_mysql(){
num=0
for host in ${hostip[@]}
do
let num+=1
if [[ `get_localip` == $host ]];then
cd $bash_path
rm -rf $database_path/mysql/
mkdir -p $database_path/mysql/{data,backup}
# cp my.cnf /opt/mysql/
chmod -R 777 $database_path/mysql
 
 docker pull registry.cn-hangzhou.aliyuncs.com/yangb/pxc && docker service create --replicas ${#hostip[*]} --name pause --network swarm_mysql_pxc mirrorgooglecontainers/pause:3.1  && docker run -d -p $outport:3306 -p 4444:4444 -p 4567:4567 -p 4568:4568 -e MYSQL_ROOT_PASSWORD=$mysql_root_password -e CLUSTER_NAME=PXC -e XTRABACKUP_PASSWORD=$mysql_root_password -v $database_path/mysql/data:/var/lib/mysql -v $database_path/mysql/backup:/data -v /etc/localtime:/etc/localtime:ro -v /var/run/docker.sock:/var/run/docker.sock --privileged --name=`hostname` -e CHARACTER-SET-SERVER=$character -e MYSQL_PASSWORD=$mysql_password -e MYSQL_DATABASE=$new_database -e MYSQL_USER=$new_user -e COLLATION-SERVER=$collation --net=swarm_mysql_pxc registry.cn-hangzhou.aliyuncs.com/yangb/pxc
	
else
  
ssh root@$host "docker pull registry.cn-hangzhou.aliyuncs.com/yangb/pxc; docker run -d -p $outport:3306 -p 4444:4444 -p 4567:4567 -p 4568:4568 -e MYSQL_ROOT_PASSWORD=$mysql_root_password -e CLUSTER_NAME=PXC -e CLUSTER_JOIN=${hostname}"1" -e XTRABACKUP_PASSWORD=$mysql_root_password -v $database_path/mysql/data:/var/lib/mysql -v $database_path/mysql/backup:/data -v /etc/localtime:/etc/localtime:ro -v /var/run/docker.sock:/var/run/docker.sock --privileged -e MYSQL_DATABASE=$new_database -e MYSQL_USER=$new_user -e CHARACTER-SET-SERVER=$character -e MYSQL_PASSWORD=$mysql_password -e COLLATION-SERVER=$collation --name=$hostname$num --net=swarm_mysql_pxc registry.cn-hangzhou.aliyuncs.com/yangb/pxc;systemctl restart keepalived" 
fi
done

systemctl restart keepalived
}


main(){
  #yum_update
  yum_config
  yum_init
  ssh_config
  iptables_config
  system_config
  ulimit_config
  #sysctl_config
  deploy_keepalived
  install_docker
  config_docker 
  #swarm_master
  
  
  change_hosts
  rootssh_trust
  
  deploy_mysql
  
  echo "mysql_pxc集群已经安装完毕，请登录相关服务器验收！"

  
}
main 
