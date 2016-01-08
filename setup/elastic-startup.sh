#!/bin/bash

readonly COMPLETION_FILE=/opt/setup.complete

# Get variables
readonly NODE_NAME=$(hostname)
readonly PROJECT_ID=$(/usr/share/google/get_metadata_value project-id)
readonly ZONE=$(/usr/share/google/get_metadata_value zone | cut -d"/" -f 4)
readonly GCM_API_KEY=$(/usr/share/google/get_metadata_value stackdriver-agent-key)
readonly CLUSTER_NAME=$(/usr/share/google/get_metadata_value attributes/CLUSTER_NAME)
readonly TARGET_POOL=$(/usr/share/google/get_metadata_value attributes/TARGET_POOL)
readonly GCS_BUCKET=$(/usr/share/google/get_metadata_value attributes/GCS_BUCKET)

function setup() {

  apt-get update

  # Download Elasticsearch
  wget https://download.elasticsearch.org/elasticsearch/elasticsearch/elasticsearch-2.1.0.deb

  # Prepare Java installation (or OpenJDK)
  apt-get install java8-runtime-headless -yqq

  # Prepare Elasticsearch installation
  dpkg -i elasticsearch-2.1.0.deb

  # Install Plugin
  cd /usr/share/elasticsearch
  bin/plugin install cloud-gce
  bin/plugin install analysis-kuromoji
  bin/plugin install mobz/elasticsearch-head
  bin/plugin install royrusso/elasticsearch-HQ

  # Install GCM agent
  apt-get install libyajl2 -yqq
  curl -L https://dl.google.com/cloudagents/install-logging-agent.sh | bash
  sudo curl -o /etc/apt/sources.list.d/stackdriver.list https://repo.stackdriver.com/jessie.list
  curl --silent https://app.google.stackdriver.com/RPM-GPG-KEY-stackdriver | sudo apt-key add -
  sudo apt-get update
  sudo apt-get install stackdriver-agent
  echo "stackdriver-agent stackdriver-agent/apikey string $GCM_API_KEY" | debconf-set-selections
  gsutil cp gs://$GCS_BUCKET/elasticsearch.conf /opt/stackdriver/collectd/etc/collectd.d/elasticsearch.conf

  # Settings
  echo "
cluster.name: $CLUSTER_NAME
node.name: $NODE_NAME
cloud:
  gce:
    project_id: $PROJECT_ID
    zone: $ZONE
discovery:
  zen.ping.multicast.enabled: false
  type: gce
  gce:
    tags: elasticsearch
path.data: /var/lib/elasticsearch/data
network:
  bind_host: 0.0.0.0
  publish_host: _gce:hostname_
" >> /etc/elasticsearch/elasticsearch.yml

  # Memory
  readonly TOTAL_MEMORY_KB=$(cat /proc/meminfo | grep MemTotal | sed 's/[A-Za-z:\t]*//g')
  readonly TOTAL_MEMORY_GB=$((TOTAL_MEMORY_KB/1000000))
  readonly ES_HEAP_SIZE=$((TOTAL_MEMORY_GB / 2))
  echo "
ES_HEAP_SIZE=${ES_HEAP_SIZE}g
MAX_OPEN_FILES=65535
MAX_LOCKED_MEMORY=unlimited
MAX_MAP_COUNT=262144
" >> /etc/default/elasticsearch

  # Complete
  touch ${COMPLETION_FILE}

}

if [ ! -e ${COMPLETION_FILE} ]; then
  setup
fi

/etc/init.d/stackdriver-agent start
systemctl start elasticsearch

#  Add self to target pools
gcloud compute target-pools add-instances $TARGET_POOL --instances $NODE_NAME --zone $ZONE
