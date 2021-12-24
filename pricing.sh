#!/bin/bash -v

#### Loading scripts
#### DO NOT CHANGE
source ./pricing_cache.sh
source ./pricing_process.sh
source ./pricing_storage_transfer_service.sh



#### Local Environment related
#### CHANGE AS NEEDED
export DIR_SCHEMA=./schema
export DIR_CACHE=./cache
export DIR_PROCESSED=./processed
export DIR_HEADERS=./headers
export DIR_SQL=./sql
export DIR_ARTIFACTS=./artifacts
export DIR_TEMP=./temp

#### DO NOT CHANGE
#if [ ! -d ${DIR_SCHEMA}     ] ; then mkdir -p ${DIR_SCHEMA}     ; fi
if [ ! -d ${DIR_CACHE}      ] ; then mkdir -p ${DIR_CACHE}      ; fi
if [ ! -d ${DIR_PROCESSED}  ] ; then mkdir -p ${DIR_PROCESSED}  ; fi
if [ ! -d ${DIR_HEADERS}    ] ; then mkdir -p ${DIR_HEADERS}    ; fi
if [ ! -d ${DIR_SQL}        ] ; then mkdir -p ${DIR_SQL}        ; fi
#if [ ! -d ${DIR_ARTIFACTS}  ] ; then mkdir -p ${DIR_ARTIFACTS}  ; fi
if [ ! -d ${DIR_TEMP}       ] ; then mkdir -p ${DIR_TEMP}       ; fi


if [ ! -d ${DIR_OUT_CONCAT} ] ; then mkdir -p ${DIR_OUT_CONCAT} ; fi
export DIR_OUT_CONCAT=${DIR_PROCESSED}/concat

## aws feeds will be cached in local directory $DIR_CACHE
## url structure of all feeds are preserved so that I don't have to think of unique file names


function clearCache {
    if [ -d "${DIR_CACHE}" ] ; then
        rm -rf "${DIR_CACHE}"/*
    fi
}
function clearHeaders {
    if [ -d "${DIR_HEADERS}" ] ; then
        rm -rf "${DIR_HEADERS}"/*
    fi
}
function clearProcessed {
    if [ -d "${DIR_PROCESSED}" ] ; then
        rm -rf "${DIR_PROCESSED}"/*
    fi
}



#### Data source (AWS) related

#### DO NOT CHANGE
export AWS_FEEDURL_PREFIX=https://pricing.us-east-1.amazonaws.com
export AWS_FEEDURL_INDEX=${AWS_FEEDURL_PREFIX}/offers/v1.0/aws/index.json

#### DO NOT CHANGE
export LOCAL_INDEX=${DIR_CACHE}/${AWS_FEEDURL_INDEX#https://}
if [ ! -d ${LOCAL_INDEX%/*} ] ; then mkdir -p ${LOCAL_INDEX%/*} ; fi


#### GCP Environment related
#### CHANGE AS NEEDED

export GCP_PROJECTNAME=$(gcloud config list  --format="value(core.project)")
#echo GCP_PROJECTNAME:"${GCP_PROJECTNAME}"

export REGION=asia-southeast1

export BUCKET=moritani-pricebook-asia-southeast1
export BUCKET_WORK=moritani-pricebook-asia-southeast1

export BQ_PROJECT=${GCP_PROJECTNAME}
export BQ_DATASET=aws_pricing
export BQ_DATASET_STAGING=aws_pricing_staging
export BQ_TABLE_PREFIX=aws_offers



#### GCP Transfer service
#### CHANGE AS NEEDED

export BUCKET_STS_SINK=moritani-pricebook-transferservice-sink-asia




#### main

## usage to be implemented

function usage {
  echo usage :

  echo $0 cacheRefreshMasterIndex
  echo $0 clearCache
  echo $0 clearHeaders
  echo $0 clearProcessed
  echo $0 pullAwsVersionIndexes
  echo $0 pullAwsVersionIndexesFull
  echo $0 pullAwsSavingsPlanVersionIndexes
  echo $0 pullAwsOfferVersion         "<OFFER>" "[<VERSION>]"
  echo $0 pullCurrentOffers
  echo $0 pullLatestOffers

  echo $0 preprocessOfferdata         "<OFFER>" "<VERSION>"
  echo $0 processAndLoadCurrentAll
  echo $0 processAndLoadOfferVersion  "<OFFER>" "[<VERSION>]"
  echo $0 processAndLoadOfferVersions "<OFFER>"
  echo $0 mergestaging2main
  echo $0 createOfferTable
  echo $0 recreateOfferTable

  echo $0 cacheAndValidate "<URL>"
  echo $0 listOfferVersionsAWS "<OFFER>"
  echo $0 listOfferVersionsBQ  "[<OFFER>]"
  echo $0 compareOfferVersions "<OFFER>"
  echo $0 listOfferVersionsMissingInBQ "<OFFER>"
  
  echo $0 createAwsOffersCurrentVersionUrlList
  echo $0 createAwsOffersLatestVersionUrlList
  echo $0 createAwsFullVersionIndexDownloadTsv
}

"$@"

if [[ "$#" == 0 ]]; then
 usage
fi