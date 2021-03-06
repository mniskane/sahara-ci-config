#!/bin/bash -x

for i in $(env | awk -F"=" '{print $1}') ; do
  if [[ $i =~ OS_ ]]; then
    unset $i
  fi
done

TOP_DIR=$(cd $(dirname "$0") && pwd)
ADMIN_RCFILE=$TOP_DIR/openrc
PRIVATE_CIDR=10.0.0.0/24
CINDER_CONF=/etc/cinder/cinder.conf
NOVA_CONF=/etc/nova/nova.conf
GLANCE_CACHE_CONF=/etc/glance/glance-cache.conf
KEYSTONE_CONF=/etc/keystone/keystone.conf
HEAT_CONF=/etc/heat/heat.conf
MYSQL_CONF=/etc/mysql/my.cnf
INTERFACE='br-ex'

source $TOP_DIR/functions-common
if [[ $(hostname -s) =~ stack-42 ]]; then
    HOST_IP='172.18.168.42'
else
    HOST_IP='172.18.168.43'
fi

VANILLA_2_7_1_IMAGE_PATH=/home/ubuntu/images/vanilla_2.7.1_u14.qcow2
CENTOS7_AMBARI_2_2_IMAGE_PATH=/home/ubuntu/images/ambari_2.2_c7.qcow2
UBUNTU_AMBARI_2_2_IMAGE_PATH=/home/ubuntu/images/ambari_2.2_u14.qcow2
UBUNTU_CDH_5_5_0_IMAGE_PATH=/home/ubuntu/images/cdh_5.5.0_u14.qcow2
CENTOS7_CDH_5_5_0_IMAGE_PATH=/home/ubuntu/images/cdh_5.5.0_c7.qcow2
UBUNTU_CDH_5_7_0_IMAGE_PATH=/home/ubuntu/images/cdh_5.7.0_u14.qcow2
CENTOS7_CDH_5_7_0_IMAGE_PATH=/home/ubuntu/images/cdh_5.7.0_c7.qcow2
UBUNTU_CDH_5_9_0_IMAGE_PATH=/home/ubuntu/images/cdh_5.9.0_u14.qcow2
CENTOS7_CDH_5_9_0_IMAGE_PATH=/home/ubuntu/images/cdh_5.9.0_c7.qcow2
SPARK_1_6_0_IMAGE_PATH=/home/ubuntu/images/spark_1.6.0_u14.qcow2
SPARK_1_6_0_MITAKA_IMAGE_PATH=/home/ubuntu/images/spark_1.6.0_u14_mitaka.qcow2
SPARK_2_1_0_IMAGE_PATH=/home/ubuntu/images/spark_2.1.0_u14.qcow2
MAPR_5_1_0_MRV2_IMAGE_PATH=/home/ubuntu/images/mapr_5.1.0.mrv2_u14.qcow2
MAPR_5_2_0_MRV2_IMAGE_PATH=/home/ubuntu/images/mapr_5.2.0.mrv2_u14.qcow2
STORM_1_0_1_IMAGE_PATH=/home/ubuntu/images/storm_1.0.1_u14.qcow2
STORM_1_1_0_IMAGE_PATH=/home/ubuntu/images/storm_1.1.0_u14.qcow2

export OS_CLOUD='devstack-admin'

# setup ci tenant and ci users
CI_TENANT_ID=$(openstack project create ci --description 'CI tenant' | grep -w id | get_field 2)
CI_USER_ID=$(openstack user create ci-user --project $CI_TENANT_ID --password nova |  grep -w id | get_field 2)
ADMIN_USER_ID=$(openstack user list | grep -w admin | get_field 1)
MEMBER_ROLE_ID=$(openstack role list | grep -w Member | get_field 1)
HEAT_OWNER_ROLE_ID=$(openstack role list | grep -w heat_stack_owner | get_field 1)
openstack role add --user $CI_USER_ID --project $CI_TENANT_ID $MEMBER_ROLE_ID
openstack role add --user $ADMIN_USER_ID --project $CI_TENANT_ID $MEMBER_ROLE_ID
#keystone user-role-add --user $CI_USER_ID --role $HEAT_OWNER_ROLE_ID --tenant $CI_TENANT_ID
#keystone user-role-add --user $ADMIN_USER_ID --role $HEAT_OWNER_ROLE_ID --tenant $CI_TENANT_ID
ADMIN_ROLE_ID=$(openstack role list | grep -w admin | get_field 1)
openstack role add --user $CI_USER_ID --project $CI_TENANT_ID $ADMIN_ROLE_ID
openstack role add --user $ADMIN_USER_ID --project $CI_TENANT_ID $ADMIN_ROLE_ID

# create qa flavor
openstack flavor create --public --id 20 --ram 2048 --disk 40 --vcpus 1 qa-flavor
openstack flavor delete m1.small
openstack flavor create --public --id 2 --ram 1024 --disk 20 --vcpus 1 m1.small

# setup quota for ci tenent in nova
openstack quota set --ram 200000 --instances 64 --cores 150 --volumes 100 --gigabytes 2000 --floating-ips 64 --secgroup-rules 10000 --secgroups 1000 $CI_TENANT_ID

# switch to ci-user credentials
source $ADMIN_RCFILE ci-user ci
export OS_CLOUD='devstack-ci'

echo "  devstack-ci:
    auth:
      auth_url: http://${HOST_IP}:35357
      password: nova
      project_domain_id: default
      project_name: ci
      user_domain_id: default
      username: ci-user
    identity_api_version: '3'
    region_name: RegionOne
" >> /etc/openstack/clouds.yaml

# setup quota for ci tenant in neutron
neutron quota-update --tenant_id $CI_TENANT_ID --port 64

# add images for tests
openstack image create $(basename -s .qcow2 $VANILLA_2_7_1_IMAGE_PATH) --file $VANILLA_2_7_1_IMAGE_PATH --disk-format qcow2 --container-format bare  --property '_sahara_tag_ci'='True' --property '_sahara_tag_2.7.1'='True' --property '_sahara_tag_vanilla'='True' --property '_sahara_username'='ubuntu'
openstack image create $(basename -s .qcow2 $CENTOS7_AMBARI_2_2_IMAGE_PATH) --file $CENTOS7_AMBARI_2_2_IMAGE_PATH --disk-format qcow2 --container-format bare  --property '_sahara_tag_ci'='True' --property '_sahara_tag_2.4'='True' --property '_sahara_tag_2.3'='True' --property '_sahara_tag_ambari'='True' --property '_sahara_username'='centos'
openstack image create $(basename -s .qcow2 $UBUNTU_AMBARI_2_2_IMAGE_PATH) --file $UBUNTU_AMBARI_2_2_IMAGE_PATH --disk-format qcow2 --container-format bare  --property '_sahara_tag_ci'='True' --property '_sahara_tag_2.4'='True' --property '_sahara_tag_2.3'='True' --property '_sahara_tag_ambari'='True' --property '_sahara_username'='ubuntu'
openstack image create $(basename -s .qcow2 $UBUNTU_CDH_5_5_0_IMAGE_PATH) --file $UBUNTU_CDH_5_5_0_IMAGE_PATH --disk-format qcow2 --container-format bare  --property '_sahara_tag_ci'='True' --property '_sahara_tag_5.5.0'='True' --property '_sahara_tag_cdh'='True' --property '_sahara_username'="ubuntu"
openstack image create $(basename -s .qcow2 $CENTOS7_CDH_5_5_0_IMAGE_PATH) --file $CENTOS7_CDH_5_5_0_IMAGE_PATH --disk-format qcow2 --container-format bare  --property '_sahara_tag_ci'='True' --property '_sahara_tag_5.5.0'='True' --property '_sahara_tag_cdh'='True' --property '_sahara_username'="centos"
openstack image create $(basename -s .qcow2 $CENTOS7_CDH_5_7_0_IMAGE_PATH) --file $CENTOS7_CDH_5_7_0_IMAGE_PATH --disk-format qcow2 --container-format bare  --property '_sahara_tag_ci'='True' --property '_sahara_tag_5.7.0'='True' --property '_sahara_tag_cdh'='True' --property '_sahara_username'="centos"
openstack image create $(basename -s .qcow2 $UBUNTU_CDH_5_7_0_IMAGE_PATH) --file $UBUNTU_CDH_5_7_0_IMAGE_PATH --disk-format qcow2 --container-format bare  --property '_sahara_tag_ci'='True' --property '_sahara_tag_5.7.0'='True' --property '_sahara_tag_cdh'='True' --property '_sahara_username'="ubuntu"
openstack image create $(basename -s .qcow2 $CENTOS7_CDH_5_9_0_IMAGE_PATH) --file $CENTOS7_CDH_5_9_0_IMAGE_PATH --disk-format qcow2 --container-format bare  --property '_sahara_tag_ci'='True' --property '_sahara_tag_5.9.0'='True' --property '_sahara_tag_cdh'='True' --property '_sahara_username'="centos"
openstack image create $(basename -s .qcow2 $UBUNTU_CDH_5_9_0_IMAGE_PATH) --file $UBUNTU_CDH_5_9_0_IMAGE_PATH --disk-format qcow2 --container-format bare  --property '_sahara_tag_ci'='True' --property '_sahara_tag_5.9.0'='True' --property '_sahara_tag_cdh'='True' --property '_sahara_username'="ubuntu"
openstack image create $(basename -s .qcow2 $SPARK_1_6_0_IMAGE_PATH) --file $SPARK_1_6_0_IMAGE_PATH --disk-format qcow2 --container-format bare  --property '_sahara_tag_ci'='True' --property '_sahara_tag_spark'='True' --property '_sahara_tag_1.6.0'='True'  --property '_sahara_username'="ubuntu"
openstack image create $(basename -s .qcow2 $SPARK_1_6_0_MITAKA_IMAGE_PATH) --file $SPARK_1_6_0_MITAKA_IMAGE_PATH --disk-format qcow2 --container-format bare  --property '_sahara_tag_ci'='True' --property '_sahara_tag_spark'='True' --property '_sahara_tag_1.6.0'='True'  --property '_sahara_username'="ubuntu"
openstack image create $(basename -s .qcow2 $SPARK_2_1_0_IMAGE_PATH) --file $SPARK_2_1_0_IMAGE_PATH --disk-format qcow2 --container-format bare  --property '_sahara_tag_ci'='True' --property '_sahara_tag_spark'='True' --property '_sahara_tag_2.1.0'='True'  --property '_sahara_username'="ubuntu"
openstack image create $(basename -s .qcow2 $MAPR_5_1_0_MRV2_IMAGE_PATH) --file $MAPR_5_1_0_MRV2_IMAGE_PATH --disk-format qcow2 --container-format bare  --property '_sahara_tag_ci'='True' --property '_sahara_tag_mapr'='True' --property '_sahara_tag_5.1.0.mrv2'='True'  --property '_sahara_username'="ubuntu"
openstack image create $(basename -s .qcow2 $MAPR_5_2_0_MRV2_IMAGE_PATH) --file $MAPR_5_2_0_MRV2_IMAGE_PATH --disk-format qcow2 --container-format bare  --property '_sahara_tag_ci'='True' --property '_sahara_tag_mapr'='True' --property '_sahara_tag_5.2.0.mrv2'='True'  --property '_sahara_username'="ubuntu"
openstack image create $(basename -s .qcow2 $STORM_1_0_1_IMAGE_PATH) --file $STORM_1_0_1_IMAGE_PATH --disk-format qcow2 --container-format bare  --property '_sahara_tag_ci'='True' --property '_sahara_tag_storm'='True' --property '_sahara_tag_1.0.1'='True'  --property '_sahara_username'="ubuntu"
openstack image create $(basename -s .qcow2 $STORM_1_1_0_IMAGE_PATH) --file $STORM_1_1_0_IMAGE_PATH --disk-format qcow2 --container-format bare  --property '_sahara_tag_ci'='True' --property '_sahara_tag_storm'='True' --property '_sahara_tag_1.1.0'='True'  --property '_sahara_username'="ubuntu"
openstack image set --name ubuntu-16.04 xenial-server-cloudimg-amd64-disk1

# rename admin private network
neutron net-update private --name admin-private
# create neutron private network for ci tenant
PRIVATE_NET_ID=$(neutron net-create private | grep -w id | get_field 2)
SUBNET_ID=$(neutron subnet-create --name ci-subnet $PRIVATE_NET_ID $PRIVATE_CIDR | grep -w id | get_field 2)
ROUTER_ID=$(neutron router-create ci-router | grep -w id | get_field 2)
PUBLIC_NET_ID=$(neutron net-list | grep -w public | get_field 1)
FORMAT=" --request-format xml"
neutron router-interface-add $ROUTER_ID $SUBNET_ID
neutron router-gateway-set $ROUTER_ID $PUBLIC_NET_ID
neutron subnet-update ci-subnet --dns_nameservers list=true 8.8.8.8 8.8.4.4

# create keypair for UI tests
#nova --os-username ci-user --os-password nova --os-tenant-name ci keypair-add public-jenkins > /dev/null

#enable auto assigning of floating ips
#ps -ef | grep -i "nova-network" | grep -v grep | awk '{print $2}' | xargs sudo kill -9
#sudo sed -i -e "s/default_floating_pool = public/&\nauto_assign_floating_ip = True/g" /etc/nova/nova.conf

# setup security groups
#this actions is workaround for bug: https://bugs.launchpad.net/neutron/+bug/1263997
#CI_DEFAULT_SECURITY_GROUP_ID=$(neutron security-group-list --tenant_id $CI_TENANT_ID | grep ' default ' | awk '{print $2}')
CI_DEFAULT_SECURITY_GROUP_ID=$(openstack security group list | grep -w default | get_field 1)
neutron security-group-rule-create --tenant_id $CI_TENANT_ID --protocol icmp --direction ingress $CI_DEFAULT_SECURITY_GROUP_ID
neutron security-group-rule-create --tenant_id $CI_TENANT_ID --protocol icmp --direction egress $CI_DEFAULT_SECURITY_GROUP_ID
neutron security-group-rule-create --tenant_id $CI_TENANT_ID --protocol tcp --port-range-min 1 --port-range-max 65535 --direction ingress $CI_DEFAULT_SECURITY_GROUP_ID
neutron security-group-rule-create --tenant_id $CI_TENANT_ID --protocol tcp --port-range-min 1 --port-range-max 65535 --direction egress $CI_DEFAULT_SECURITY_GROUP_ID
neutron security-group-rule-create --tenant_id $CI_TENANT_ID --protocol udp --port-range-min 1 --port-range-max 65535 --direction egress $CI_DEFAULT_SECURITY_GROUP_ID
neutron security-group-rule-create --tenant_id $CI_TENANT_ID --protocol udp --port-range-min 1 --port-range-max 65535 --direction ingress $CI_DEFAULT_SECURITY_GROUP_ID

#create Sahara endpoint for tests
service_id=$(openstack service create data_processing --name sahara --description "Data Processing Service" | grep -w id | get_field 2)
openstack endpoint create $service_id public 'http://localhost:8386/v1.1/$(tenant_id)s' --region RegionOne
openstack endpoint create $service_id admin 'http://localhost:8386/v1.1/$(tenant_id)s' --region RegionOne
openstack endpoint create $service_id internal 'http://localhost:8386/v1.1/$(tenant_id)s' --region RegionOne
# create second endpoint due to bug: #1356053
service_id=$(openstack service create data-processing --name sahara --description "Data Processing Service" | grep -w id | get_field 2)
openstack endpoint create $service_id public 'http://localhost:8386/v1.1/$(tenant_id)s' --region RegionOne
openstack endpoint create $service_id admin 'http://localhost:8386/v1.1/$(tenant_id)s' --region RegionOne
openstack endpoint create $service_id internal 'http://localhost:8386/v1.1/$(tenant_id)s' --region RegionOne

#setup expiration time for keystone
iniset $KEYSTONE_CONF token expiration 86400
sudo service apache2 restart

iniset $GLANCE_CACHE_CONF DEFAULT image_cache_stall_time 43200
iniset $NOVA_CONF DEFAULT disk_allocation_ratio 10.0
iniset $NOVA_CONF DEFAULT ram_allocation_ratio 10.0

#Setup Heat
iniset $HEAT_CONF database max_pool_size 1000
iniset $HEAT_CONF database max_overflow  1000

# Setup path for Nova instances
#iniset $NOVA_CONF DEFAULT instances_path '/srv/nova'

# set mysql max allowed connections to 1000
sudo bash -c "source $TOP_DIR/functions && \
    iniset $MYSQL_CONF mysqld max_connections 1000"
sudo service mysql restart
sleep 5

# add squid iptables rule if not exists
squid_port="3128"
sudo iptables-save | grep "$squid_port"
if [ "$?" == "1" ]; then
  sudo iptables -t nat -A PREROUTING -i ${INTERFACE} -p tcp --dport 80 -m comment --comment "Redirect traffic to Squid" -j DNAT --to ${HOST_IP}:$squid_port
fi

# Restart OpenStack services
screen -X -S stack quit
echo "Kill all python processes"
# shellcheck disable=SC2009
ps aux | pgrep -f python | sudo xargs kill -9
screen -dm -c $TOP_DIR/stack-screenrc
sleep 10

echo "|---------------------------------------------------|"
echo "| ci-tenant-id | $CI_TENANT_ID"
echo "|---------------------------------------------------|"
echo "| ci-private-network-id | $PRIVATE_NET_ID"
echo "|---------------------------------------------------|"
