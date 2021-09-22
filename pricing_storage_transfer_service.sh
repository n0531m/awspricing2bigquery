#!/bin/bash 

function createAwsCurrentVersionsDownloadlist {
  local FILE_CACHE=cached_index.json
  local DIR_OUTPUT=./indexes

  local DIR_CACHE=./cache

  local AWS_FEEDURL_PREFIX=https://pricing.us-east-1.amazonaws.com
  #wget -q -P ./indexes -c -x ${AWS_FEEDURL_PREFIX}/offers/v1.0/aws/index.json
  wget -q -O $FILE_CACHE -c ${AWS_FEEDURL_PREFIX}/offers/v1.0/aws/index.json
  for AWS_OFFER in $(cat $FILE_CACHE | jq -r '.offers[] | .offerCode' | sort)
  do 
    #echo ${AWS_FEEDURL_PREFIX}/offers/v1.0/aws/${AWS_OFFER}/index.json
    #echo ${AWS_FEEDURL_PREFIX}/offers/v1.0/aws/${AWS_OFFER}/current/index.json
    #local versionIndexUrl=$(cat $FILE_CACHE | jq --arg offer $AWS_OFFER -r ".offers | .[\$offer] | .versionIndexUrl")
    local versionIndexUrl=${AWS_FEEDURL_PREFIX}/offers/v1.0/aws/${AWS_OFFER}/index.json
    local versionIndexPath=$(awsUrlToLocalPath $versionIndexUrl) 
    #echo $versionIndexUrl
    #offerVersionUrl=$(curl -s $versionIndexUrl | jq -r '[.versions[]] | sort_by(.offerVersionUrl)[-1].offerVersionUrl')
    offerVersionUrl=$(cat $versionIndexPath | jq -r '[.versions[]] | sort_by(.offerVersionUrl)[-1].offerVersionUrl')
    VERSION=${offerVersionUrl%/index.json}
    VERSION=${VERSION##*/}
    echo ${AWS_FEEDURL_PREFIX}${offerVersionUrl}
    #echo ${AWS_FEEDURL_PREFIX}/offers/v1.0/aws/${AWS_OFFER}/current/region_index.json
  done > downloadlistCurrentVersions.txt
  #| xargs -n 2 -P 0 wget -P ./indexes -c -x
  #wget -q -P ./indexes -c -x -i downloadlistVersionIndex.txt
  cat downloadlistCurrentVersions.txt | xargs -n 2 -P 0 wget -q -P ${DIR_OUTPUT} -c -x
}
function createAwsLatestPricingDownloadlist {
  FILE_CACHE=cached_index.json
  local FILE_OUTPUT=./artifacts/latestVersionIndexlist.txt

  local AWS_FEEDURL_PREFIX=https://pricing.us-east-1.amazonaws.com
  wget -q -O $FILE_CACHE -c ${AWS_FEEDURL_PREFIX}/offers/v1.0/aws/index.json
  for AWS_OFFER in $(cat $FILE_CACHE | jq -r '.offers[] | .offerCode' | sort)
  do 
    #AWS_OFFER=AmazonKinesisFirehose
    local versionIndexUrl=$(curl -s $AWS_FEEDURL_PREFIX/offers/v1.0/aws/index.json \
      | jq --arg offer $AWS_OFFER -r ".offers | .[\$offer] | .versionIndexUrl")
    #echo $AWS_FEEDURL_PREFIX$versionIndexUrl
    local offerVersionUrl=$(curl -s $AWS_FEEDURL_PREFIX$versionIndexUrl | jq -r '[.versions[]] | sort_by(.offerVersionUrl)[-1].offerVersionUrl')
    #echo $AWS_FEEDURL_PREFIX$offerVersionUrl
    VERSION=${offerVersionUrl%/index.json}
    VERSION=${VERSION##*/}
    #${VERSION##*/}index.json
    #echo $VERSION
    
    local DIR_DOWNLOAD=$DATADIR/$CLOUD/downloaded
    local FILE_DOWNLOAD=$DIR_DOWNLOAD/${AWS_OFFER}_${VERSION}.json
    if (( VERSION > 20210101000000 )) ; then
      echo ${AWS_FEEDURL_PREFIX}${offerVersionUrl}
    fi
    #echo $FILE_DOWNLOAD
    #downloadAwsPricing $AWS_OFFER
  done > ${FILE_OUTPUT}
}

function createAwsFullVersionIndexDownloadTsv {
  #https://cloud.google.com/storage-transfer/docs/create-url-list
  local FILE_OUTPUT=./artifacts/fullVersionIndexlist.tsv
  
  echo TsvHttpData-1.0 > $FILE_OUTPUT
  local FILE_CACHE=cached_index.json
  local AWS_FEEDURL_PREFIX=https://pricing.us-east-1.amazonaws.com
  wget -q -P ./indexes -c -x ${AWS_FEEDURL_PREFIX}/offers/v1.0/aws/index.json
  wget -q -O $FILE_CACHE -c ${AWS_FEEDURL_PREFIX}/offers/v1.0/aws/index.json
  for AWS_OFFER in $(cat $FILE_CACHE | jq -r '.offers[] | .offerCode' | sort)
  do 
    for offerVersionUrl in $(curl -s "${AWS_FEEDURL_PREFIX}/offers/v1.0/aws/${AWS_OFFER}/index.json" | jq -r .versions[].offerVersionUrl)
    do
      ## Content-Length
      local CLEN=$(curl -s -I "${AWS_FEEDURL_PREFIX}${offerVersionUrl}" | grep Content-Length | cut -f 2 -d " " | tr -d "\r\n")
      ## ETag (hex --> binary --> Base64)
      local ETag=$(curl -s -I "${AWS_FEEDURL_PREFIX}${offerVersionUrl}" | grep ETag | cut -f 2 -d " " | tr -d "\"" | xxd -r -p | base64)
      echo -e "${AWS_FEEDURL_PREFIX}${offerVersionUrl}\t${CLEN}\t${ETag}"
    done
  done 
  #| sort >> $FILE_OUTPUT

  #gsutil cp -c $FILE_OUTPUT gs://moritani-pricebook-transferservice-sink-asia/lists/fullVersionIndexlist_sorted.txt
}