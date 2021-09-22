#!/bin/bash

source ./pricing_cache.sh
source ./pricing_process.sh
source ./pricing_storage_transfer_service.sh



#### Local Environment related

export DIR_SCHEMA=./schema
export DIR_CACHE=./cache
export DIR_PROCESSED=./processed
export DIR_HEADERS=./headers
export DIR_SQL=./sql
export DIR_TEMP=./temp

  if [ ! -d ${DIR_SCHEMA}    ] ; then mkdir -p ${DIR_SCHEMA}     ; fi
  if [ ! -d ${DIR_CACHE}     ] ; then mkdir -p ${DIR_CACHE}      ; fi
  if [ ! -d ${DIR_PROCESSED} ] ; then mkdir -p ${DIR_PROCESSED}  ; fi
  if [ ! -d ${DIR_HEADERS}   ] ; then mkdir -p ${DIR_HEADERS}    ; fi
  if [ ! -d ${DIR_SQL}       ] ; then mkdir -p ${DIR_SQL}        ; fi
  if [ ! -d ${DIR_TEMP}      ] ; then mkdir -p ${DIR_TEMP}       ; fi


DIR_OUT_CONCAT=${DIR_PROCESSED}/concat
if [ ! -d ${DIR_OUT_CONCAT}  ] ; then mkdir -p ${DIR_OUT_CONCAT} ; fi


#### Data source (AWS) related


AWS_FEEDURL_PREFIX=https://pricing.us-east-1.amazonaws.com
AWS_FEEDURL_INDEX=${AWS_FEEDURL_PREFIX}/offers/v1.0/aws/index.json

LOCAL_INDEX=${DIR_CACHE}/${AWS_FEEDURL_INDEX#https://}
if [ ! -d ${LOCAL_INDEX%/*} ] ; then mkdir -p ${LOCAL_INDEX%/*} ; fi


#### GCP Environment related

GCP_PROJECTNAME=$(gcloud config list  --format="value(core.project)")
echo GCP_PROJECTNAME:"${GCP_PROJECTNAME}"

REGION=asia-southeast1

BUCKET=moritani-pricebook-asia-southeast1
BUCKET_WORK=moritani-pricebook-asia-southeast1

BQ_PROJECT=${GCP_PROJECTNAME}
BQ_DATASET=aws_pricing
BQ_DATASET_STAGING=aws_pricing_staging
BQ_TABLE_PREFIX=aws_offers



####






