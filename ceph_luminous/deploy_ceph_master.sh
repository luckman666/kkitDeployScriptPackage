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

echo -e "\033[31m 这个是ceph集群脚本！欢迎关注我的个人公众号“devops的那些事”获得更多实用工具！Please continue to enter or ctrl+C to cancel \033[0m"
sleep 5
#yum update
yum_update(){
	yum update -y
}
#configure yum source
yum_config(){

  yum install wget epel-release -y
  
  if [[ $aliyun == "1" ]];then
  cd /etc/yum.repos.d/ && mkdir bak && mv -f *.repo bak/
  wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo
  wget -O /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-7.repo
  yum clean all && yum makecache

  fi
  
}

yum_init(){
while true ; do
yum -y install iotop iftop yum-utils net-tools rsync git lrzsz expect gcc gcc-c++ make cmake libxml2-devel openssl-devel curl curl-devel unzip sudo ntp libaio-devel wget vim ncurses-devel autoconf automake zlib-devel  python-devel bash-completion
if [[ $? == 0 ]] ; then
echo "mon configfile no ready sleep one second"!
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
}

ssh_config(){

if [[ `grep 'UserKnownHostsFile' /etc/ssh/ssh_config` ]];then
echo "pass"
else
sed -i "2i StrictHostKeyChecking no\nUserKnownHostsFile /dev/null" /etc/ssh/ssh_config
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
echo $host `hostname` >> /etc/hosts
else
echo $host $hostname$num >> /etc/hosts
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

# config docker
config_docker(){
sed -i "/^ExecStart/cExecStart=\/usr\/bin\/dockerd -H tcp:\/\/0\.0\.0\.0:2375 -H unix:\/\/\/var\/run\/docker.sock" /usr/lib/systemd/system/docker.service
systemctl daemon-reload
systemctl restart docker.service
}

pull_ceph_image(){
docker pull registry.cn-hangzhou.aliyuncs.com/yangb/ceph_luminous
}


deploy_ceph_mon(){
test -d $ceph_base_path/logs/ || mkdir -p $ceph_base_path/{etc,lib,logs}
chmod -R 777 $ceph_base_path/logs/

docker ps | grep -w mon && continue
docker ps -a | grep -w mon && docker rm -f mon

docker run -d --net=host --name=mon \
--privileged=true \
-v $ceph_base_path/etc/:/etc/ceph \
-v $ceph_base_path/lib/:/var/lib/ceph \
-v $ceph_base_path/logs/:/var/log/ceph/ \
-e MON_IP=$masterip \
-e CEPH_PUBLIC_NETWORK=$ceph_public_network \
registry.cn-hangzhou.aliyuncs.com/yangb/ceph_luminous mon

}

config_ceph(){
while true ; do
test -f $ceph_base_path/etc/ceph.conf 
if [[ $? == 0 ]] ; then
cat >> $ceph_base_path/etc/ceph.conf <<EOF
# 容忍更多的时钟误差
mon clock drift allowed = 2
mon clock drift warn backoff = 30
# 允许删除pool
mon_allow_pool_delete = true
uster networkbd_default_features = 3
[mgr]
# 开启WEB仪表盘
mgr modules = dashboard
EOF
break;
else
sleep 1
echo "mon configfile not ready sleep one second"!
fi
done
}

config_ceph_command(){
docker restart mon
echo 'alias ceph="docker exec mon ceph"' >> /etc/profile
echo 'alias ceph-volume="docker exec mon ceph-volume"' >> /etc/profile
echo 'alias ss="docker exec rgw ss"' >> /etc/profile
echo 'alias rbd="docker exec mon rbd"' >> /etc/profile
echo 'alias rados="docker exec mon rados"' >> /etc/profile
source /etc/profile
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

ssh root@$host "mkdir -p $ceph_base_path/{etc,lib}"

scp  $ceph_base_path/etc/*   root@$host:$ceph_base_path/etc/
scp -r $ceph_base_path/lib/bootstrap-*   root@$host:$ceph_base_path/lib/
ssh root@$host "chown -R 167:167 $ceph_base_path"

scp base.config hwclock_ntp.sh deploy_ceph_node.sh ssh_trust_init.exp ssh_trust_add.exp root@$host:/root && scp /etc/hosts root@$host:/etc/hosts && ssh root@$host "hostnamectl set-hostname $hostname$num" && ssh root@$host /root/hwclock_ntp.sh && ssh root@$host /root/deploy_ceph_node.sh && ssh root@$host "rm -rf base.config hwclock_ntp.sh deploy_ceph_node.sh ssh_trust_init.exp ssh_trust_add.exp"

fi
done
}

###########OSD #############
# scan_disk
scan_disk(){
for i in /sys/class/scsi_host/host*/scan;do echo "- - -" >$i;done
}


deploy_osd(){
num=0
#bluesstore_num=0
for odisk in  ${osddisk[@]};do  
let num+=1

docker run --rm --privileged=true \
-v $disk_path/:/dev/ \
-e OSD_DEVICE=$disk_path/$odisk \
registry.cn-hangzhou.aliyuncs.com/yangb/ceph_luminous zap_device

if [[ $bluestore == 1 ]];then
if [[ $num -le ${#bluestore_name[@]} ]];then

docker run --rm --privileged=true \
-v $disk_path/:/dev/ \
-e OSD_DEVICE=$disk_path/$bluestore_name \
registry.cn-hangzhou.aliyuncs.com/yangb/ceph_luminous zap_device

fi

docker run -d --net=host --name=$odisk --privileged=true \
-v $ceph_base_path/etc/:/etc/ceph \
-v $ceph_base_path/lib/:/var/lib/ceph \
-v $disk_path/:/dev/ \
-e OSD_DEVICE=$disk_path/$odisk \
-e OSD_TYPE=disk \
-e OSD_BLUESTORE=1 \
-e OSD_BLUESTORE_BLOCK_WAL=$disk_path/$bluestore_name \
-e OSD_BLUESTORE_BLOCK_DB=$disk_path/$bluestore_name \
-e CLUSTER=ceph registry.cn-hangzhou.aliyuncs.com/yangb/ceph_luminous osd_ceph_disk

else

docker run -d --net=host --name=$odisk --privileged=true \ 
-v $ceph_base_path/etc/:/etc/ceph \
-v $ceph_base_path/lib/:/var/lib/ceph \
-v $disk_path/:/dev/ \
-e OSD_DEVICE=$disk_path/$odisk \
-e OSD_TYPE=disk \
-e CLUSTER=ceph registry.cn-hangzhou.aliyuncs.com/yangb/ceph_luminous osd_ceph_disk

fi
done

}


deploy_rgw(){
docker run \
-d --net=host \
--name=rgw \
-v $ceph_base_path/etc/:/etc/ceph \
-v $ceph_base_path/lib/:/var/lib/ceph  \
registry.cn-hangzhou.aliyuncs.com/yangb/ceph_luminous rgw  

}

deploy_mgr(){
docker run \
-d --net=host  \
--name=mgr \
-v $ceph_base_path/etc/:/etc/ceph \
-v $ceph_base_path/lib/:/var/lib/ceph \
registry.cn-hangzhou.aliyuncs.com/yangb/ceph_luminous mgr
source /etc/profile
docker exec mon ceph mgr module enable dashboard
docker exec mon ceph config-key put mgr/dashboard/server_addr $mgr_ip
docker exec mon ceph config-key put mgr/dashboard/server_port $mgr_monitor_port #指定为7000端口，这里可以自定义修改

}

deploy_portainer(){
docker run -d -p $portainer_port:9000 --name=portainer --restart=always  -v /opt/portainer_data:/data -v /var/run/docker.sock:/var/run/docker.sock portainer/portainer	
}

main(){
 #yum_update
  yum_config
  yum_init
  ssh_config
  iptables_config
  system_config
  ulimit_config
  change_hosts
  install_docker
  config_docker
  
  pull_ceph_image
  deploy_ceph_mon
  config_ceph
  config_ceph_command

  rootssh_trust
  
if [[ $osd == "1" ]];then
scan_disk
deploy_osd
fi

if [[ $rgw == "1" ]];then
deploy_rgw
fi

if [[ $mgr == "1" ]];then
deploy_mgr
fi
if [[ $portainer == "1" ]];then   
deploy_portainer    
fi     
    
  
}
main > ./setup.log 2>&1
