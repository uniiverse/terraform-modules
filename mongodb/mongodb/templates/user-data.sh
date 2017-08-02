#!/bin/bash -v

# internal EC2 short hostname won't resolve via .tmcs nameservers
hostname ${hostname}

#
# apt
#
DEBIAN_FRONTEND=noninteractive apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 0C49F3730359A14518585931BC711F9BA15703C6
echo "deb [ arch=amd64 ] http://repo.mongodb.com/apt/ubuntu trusty/mongodb-enterprise/3.4 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-enterprise.list
DEBIAN_FRONTEND=noninteractive apt-key update -y
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y awscli
DEBIAN_FRONTEND=noninteractive apt-get install -y ntp

#
# RAID-0 local ephemeral SSDs on /data
#
if [ "${config_ephemeral}" == "true" ]; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y mdadm
  umount /mnt

  mkdir -p /opt
  yes | mdadm --create --verbose /dev/md0 --level=0 --name=opt --raid-devices=2 /dev/xvdb /dev/xvdc
  mkfs.ext4 -L opt /dev/md0
  mount LABEL=opt /opt
fi

#
# EBS SSDs for persistence on /opt
#
if [ "${config_ebs}" == "true" ]; then

  # wait until the volume is attached
  while [ ! -e /dev/xvdz ]; do
    echo "Waiting for EBS /dev/xvdz volume to attach to instance .. "
    sleep 1;
  done
  mkdir -p /opt

  #
  # IMPORTANT: only format the volume if uninitialized (i.e. first boot for a fresh volume)
  #
  parted /dev/xvdz print || mkfs.ext4 -L opt /dev/xvdz
  mount LABEL=opt /opt
fi

#
# MongoDB Tuning
#
echo LC_ALL=\"en_US.UTF-8\" >> /etc/default/locale

# kernel tuning recommended by MongoDB
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag

# shorter keepalives, 120s recommended for MongoDB in official docs:
# https://docs.mongodb.org/manual/faq/diagnostics/#does-tcp-keepalive-time-affect-mongodb-deployments
sysctl -w net.ipv4.tcp_keepalive_time=120
cat << EOF > /etc/sysctl.conf
net.ipv4.tcp_keepalive_time = 120
fs.file-max = 65536
EOF
sysctl -p

# MongoDB prefers file limits > 20,000
cat << EOF > /etc/security/limits.conf
* soft     nproc          65535
* hard     nproc          65535
* soft     nofile         65535
* hard     nofile         65535
EOF

# NUMA for MongoDB optimizations when supported
DEBIAN_FRONTEND=noninteractive apt-get install -y numactl

# required to avoid:
# "mongod: error while loading shared libraries: libnetsnmpmibs.so.30: cannot open shared object file: No such file or directory"
DEBIAN_FRONTEND=noninteractive apt-get install -y libsnmp-dev

# used by OpsManager
DEBIAN_FRONTEND=noninteractive apt-get install -y munin-node
echo "allow ^10\..*$" >> /etc/munin/munin-node.conf
ln -s /usr/share/munin/plugins/iostat /etc/munin/plugins/iostat
ln -s /usr/share/munin/plugins/iostat_ios /etc/munin/plugins/iostat_ios
/etc/init.d/munin-node restart

#
# OpsManager Agent
#
if [ "${role_opsmanager}" == "true" ]; then

  # Install MongoDB
  DEBIAN_FRONTEND=noninteractive apt-get install -y mongodb-enterprise=${mongodb_version} mongodb-enterprise-server=${mongodb_version} mongodb-enterprise-shell=${mongodb_version} mongodb-enterprise-mongos=${mongodb_version} mongodb-enterprise-tools=${mongodb_version}

  # prevent unintended upgrades by pinning the package
  echo "mongodb-enterprise hold" | dpkg --set-selections
  echo "mongodb-enterprise-server hold" | dpkg --set-selections
  echo "mongodb-enterprise-shell hold" | dpkg --set-selections
  echo "mongodb-enterprise-mongos hold" | dpkg --set-selections
  echo "mongodb-enterprise-tools hold" | dpkg --set-selections

  # NOTE: it sets mongodb user for everything inside! ("/opt/mongo")
  mkdir -p ${mongodb_basedir}
  chown mongodb:mongodb -R ${mongodb_basedir}

  # explicit default owner for parent directory ("/opt")
  chown root:root "$(dirname "${mongodb_basedir}")"

  # NOTE: it sets the permission for everything inside! (in "/opt")
  chmod 755 -R "$(dirname "${mongodb_basedir}")"

  # ensure ./mongo/data directory exists
  mkdir -p ${mongodb_basedir}/data
  chown mongodb:mongodb ${mongodb_basedir}/data

  # setup mongodb.key
  ENC_KEY_PATH=${mongodb_basedir}/mongodb.key
  aws s3 --region=${aws_region} cp ${mongodb_key_s3_object} $ENC_KEY_PATH
  chmod 600 $ENC_KEY_PATH
  chown mongodb:mongodb $ENC_KEY_PATH

  cat << EOF > /etc/mongod.conf
storage:
  dbPath: ${mongodb_basedir}/data
  journal:
    enabled: true
  engine: ${mongodb_conf_engine}

systemLog:
  destination: file
  logAppend: true
  path: ${mongodb_conf_logpath}

net:
  bindIp: 0.0.0.0
  port: 27017

security:
   keyFile: "$ENC_KEY_PATH"

replication:
   replSetName: ${mongodb_conf_replsetname}
   oplogSizeMB: ${mongodb_conf_oplogsizemb}
EOF

  service mongod stop
  service mongod start

  curl -k -OL https://downloads.mongodb.com/on-prem-mms/deb/mongodb-mms_3.4.5.424-1_x86_64.deb
  DEBIAN_FRONTEND=noninteractive dpkg --force-confold --install mongodb-mms_3.4.5.424-1_x86_64.deb

  cat << EOF > ${mongodb_basedir}/mms/conf/conf-mms.properties
mongo.mongoUri=mongodb://mms-admin:${mms_password}@opsmanager-node-1.universe.com,opsmanager-node-2.universe.com,opsmanager-node-3.universe.com/?replicaSet=${mongodb_conf_replsetname}&maxPoolSize=150
mongo.ssl=false
mms.centralUrl=http://${opsmanager_subdomain}:8080
EOF

  MMS_KEY_PATH=${mongodb_basedir}/mongodb-mms.key
  aws s3 --region=${aws_region} cp ${opsmanager_key_s3_object} $MMS_KEY_PATH
  chmod 600 $MMS_KEY_PATH
  chown mongodb-mms:mongodb-mms $MMS_KEY_PATH
  REGEX=`echo $MMS_KEY_PATH | awk '{gsub("/", "\\\/");print}'`
  sed -i "s/ENC_KEY_PATH=.*/ENC_KEY_PATH=$REGEX/" ${mongodb_basedir}/mms/conf/mms.conf

  # ensure that ./mongo/backup directory exists to allow Backup Daemon to work on backups (mongodb-mms user)
  mkdir -p ${mongodb_basedir}/backup/snapshots
  chown mongodb-mms:mongodb-mms -R ${mongodb_basedir}/backup

  # ensure that ./mongo/snapshots directory exists to allow Backup Daemon to store snapshots (mongodb-mms user)
  mkdir -p ${mongodb_basedir}/snapshots
  chown mongodb-mms:mongodb-mms -R ${mongodb_basedir}/snapshots

  service mongodb-mms stop
  service mongodb-mms start # NOTE: run mv /opt/mongodb/mms /opt/mongodb/mms-old if it fails and try to reinstall again
fi

#
# Automation Agent (requires OpsManager available)
#
if [ "${role_node}" == "true" ]; then
  curl -k -OL http://${opsmanager_subdomain}:8080/download/agent/automation/mongodb-mms-automation-agent-manager_3.2.12.2107-1_amd64.deb
  DEBIAN_FRONTEND=noninteractive dpkg --install mongodb-mms-automation-agent-manager_3.2.12.2107-1_amd64.deb

  mkdir -p ${mongodb_basedir}
  chown mongodb:mongodb ${mongodb_basedir}

  REGEX=`echo http://${opsmanager_subdomain}:8080 | awk '{gsub("/", "\\\/");print}'`
  sed -i "s/mmsBaseUrl=.*/mmsBaseUrl=$REGEX/" /etc/mongodb-mms/automation-agent.config
  sed -i "s/mmsGroupId=.*/mmsGroupId=${mms_group_id}/" /etc/mongodb-mms/automation-agent.config
  sed -i "s/mmsApiKey=.*/mmsApiKey=${mms_api_key}/" /etc/mongodb-mms/automation-agent.config

  # give DNS a chance to load, required for Automation Agent
  # otherwise, fails promptly in /var/log/mongodb-mms-automation/automation-agent-fatal.log
  # while ! nslookup ${hostname}; do
  #   echo "Waiting for hostname ${hostname} to resolve .. "
  #   sleep 1;
  # done
  # sleep 20

  # Automation Agent won't start without proper hostname resolution, but Route53 takes a few mins to propagate.
  echo "`curl http://169.254.169.254/latest/meta-data/local-ipv4` ${hostname}" >> /etc/hosts

  # setup ssl certificates for mongodb
  SSL_PATH=/etc/mongodb/ssl
  mkdir -p $SSL_PATH
  aws s3 --region=${aws_region} cp ${ssl_ca_key_s3_object} $SSL_PATH/CAroot.pem
  aws s3 --region=${aws_region} cp ${ssl_mongod_key_s3_object} $SSL_PATH/mongod.pem
  aws s3 --region=${aws_region} cp ${ssl_agent_key_s3_object} $SSL_PATH/agent.pem
  chmod 700 -R $SSL_PATH
  chown -R mongodb:mongodb $SSL_PATH

  service mongodb-mms-automation-agent stop
  service mongodb-mms-automation-agent start
fi

#
# Backup Node (connects to OpsManager)
#
if [ "${role_backup}" == "true" ]; then
  cat << EOF > /etc/mongod-backup.conf
storage:
  dbPath: ${mongodb_basedir}/backup-data
  journal:
    enabled: true
  engine: wiredTiger

systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb-backup/mongod.log

net:
  bindIp: 0.0.0.0
  port: 27018

security:
   keyFile: "${mongodb_basedir}/mongodb.key"

replication:
   replSetName: opsmanagerBackup
   oplogSizeMB: 16384
EOF
  mkdir -p ${mongodb_basedir}/backup-data
  chown mongodb:mongodb ${mongodb_basedir}/backup-data

  cp /etc/init/mongod.conf /etc/init/mongod-backup.conf
  sed -i "s/\/var\/lib\/mongodb/\/var\/lib\/mongodb-backup/g" /etc/init/mongod-backup.conf
  sed -i "s/\/var\/log\/mongodb/\/var\/log\/mongodb-backup/g" /etc/init/mongod-backup.conf
  sed -i "s/\/var\/run\/mongodb/\/var\/run\/mongodb-backup/g" /etc/init/mongod-backup.conf
  sed -i "s/\/etc\/mongod.conf/\/etc\/mongod-backup.conf/g" /etc/init/mongod-backup.conf
  sed -i "s/\/etc\/default\/mongod/\/etc\/default\/mongod-backup/g" /etc/init/mongod-backup.conf
  service mongod-backup start
fi
