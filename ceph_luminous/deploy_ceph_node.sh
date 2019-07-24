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

echo -e "\033[31m 这个是ceph集群脚本！Please continue to enter or ctrl+C to cancel \033[0m"
#sleep 5
#yum update
yum_update(){
	yum update -y
}
#configure yum source
yum_config(){
  yum install wget epel-release -y
  
if [[ $aliyun == "1" ]]; then
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
#  yum -y install chrony && systemctl start chronyd.service && systemctl enable chronyd.service
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
test -d $ceph_base_path/logs/ || mkdir -p $ceph_base_path/logs/
chmod -R 777 $ceph_base_path/logs/

docker run -d --net=host --name=mon \
--privileged=true \
-v $ceph_base_path/etc/:/etc/ceph \
-v $ceph_base_path/lib/:/var/lib/ceph \
-v $ceph_base_path/logs/:/var/log/ceph/ \
-e MON_IP=`get_localip` \
-e CEPH_PUBLIC_NETWORK=$ceph_public_network \
registry.cn-hangzhou.aliyuncs.com/yangb/ceph_luminous mon

}

config_ceph_command(){
echo 'alias ceph="docker exec mon ceph"' >> /etc/profile
echo 'alias ceph-volume="docker exec mon ceph-volume"' >> /etc/profile
echo 'alias ss="docker exec rgw ss"' >> /etc/profile
echo 'alias rbd="docker exec mon rbd"' >> /etc/profile
echo 'alias rados="docker exec mon rados"' >> /etc/profile
source /etc/profile
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
#let bluesstore_num+=1
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



#ssh trust
rootssh_trust(){
#rm -rf ~/.ssh
cd $bash_path
for host in ${hostip[@]}
do
if [[ `get_localip` != $host ]];then
#ls /root/.ssh
if [[ ! -f /root/.ssh/id_rsa.pub ]];then
expect ssh_trust_init.exp $root_passwd $host
else
expect ssh_trust_add.exp $root_passwd $host
fi
echo "remote machine root user succeed!!!!!!!!!!!!!!!! "
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
 
 ulimit_config
 install_docker
 config_docker
 pull_ceph_image
 deploy_ceph_mon
 config_ceph_command

 
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
    
if [[ $bothway == "1" ]];then
 rootssh_trust
fi
}
main > ./setup.log 2>&1
