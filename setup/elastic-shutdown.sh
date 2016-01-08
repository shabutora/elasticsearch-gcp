#!/bin/bash

# Get variables
readonly NODE_NAME=$(hostname)
readonly ZONE=$(/usr/share/google/get_metadata_value zone | cut -d"/" -f 4)
readonly TARGET_POOL=$(/usr/share/google/get_metadata_value attributes/TARGET_POOL)

gcloud compute target-pools remove-instances $TARGET_POOL --instances $NODE_NAME --zone $ZONE

systemctl stop Elasticsearch
