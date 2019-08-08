#!/usr/bin/env bash
#b8_yang@163.com
#. /etc/profile
source $bash_path/base.config
yum -y install chrony && \
sed -i "7i server  $masterip iburst\nallow $cluster_network" /etc/chrony.conf
systemctl start chronyd.service && systemctl enable chronyd.service
systemctl restart chronyd.service
