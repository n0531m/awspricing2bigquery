#!/bin/bash 


function createAwsOffersCurrentVersionUrlList {

  local FILE_OUTPUT=${DIR_ARTIFACTS}/offersCurrentVersionUrls.txt
  
  cat $LOCAL_INDEX \
  | jq -r --arg prefix ${AWS_FEEDURL_PREFIX} '.offers[] | $prefix+"/offers/v1.0/aws/"+.offerCode+"/current/index.json"' \
  | sort > ${FILE_OUTPUT}

}
function createAwsOffersLatestVersionUrlList {
  
  local FILE_OUTPUT=${DIR_ARTIFACTS}/offersLatestVersionUrls.txt
  
  cat $LOCAL_INDEX \
  | jq -r --arg prefix ${DIR_CACHE}/${AWS_FEEDURL_PREFIX#https://} '.offers[] | $prefix+"/offers/v1.0/aws/"+.offerCode+"/index.json"' \
  | xargs -n 2 -P 0 -I {}  cat {} | jq -r  --arg prefix ${AWS_FEEDURL_PREFIX} '.currentVersion as $ver | .versions[$ver] | $prefix+.offerVersionUrl' \
  | sort > ${FILE_OUTPUT}
}

function cacheHeadersFullVersionIndex {
  cat $LOCAL_INDEX | jq --arg prefix ${AWS_FEEDURL_PREFIX} -r '.offers[] | $prefix+"/offers/v1.0/aws/"+.offerCode+"/index.json"' \
  | xargs -n 2 -P 0 -I {} curl -s {} \
  | jq --arg prefix ${AWS_FEEDURL_PREFIX} -r '.versions[] | $prefix+.offerVersionUrl' \
  | xargs -n 2 -P 0 -I {} bash -c "cacheHeaderByUrl {}" 
}

function createAwsFullVersionIndexDownloadTsv {
  #https://cloud.google.com/storage-transfer/docs/create-url-list
  local FILE_OUTPUT=${DIR_ARTIFACTS}/fullVersionIndexlist.tsv
    
  cacheHeadersFullVersionIndex
  
  echo TsvHttpData-1.0 > "$FILE_OUTPUT"

  for AWS_OFFER in $(cat "$LOCAL_INDEX" | jq -r '.offers[] | .offerCode' | sort)
  do
    for offerVersionUrl in $(cat "${DIR_CACHE}/${AWS_FEEDURL_PREFIX#https://}/offers/v1.0/aws/${AWS_OFFER}/index.json" | jq -r .versions[].offerVersionUrl)
    do
      local URL="${AWS_FEEDURL_PREFIX}${offerVersionUrl}"
      #cacheHeaderByUrl $URL
      local FILE_HEADER=${DIR_HEADERS}/${URL#https://}
      if [ -s "$FILE_HEADER" ] ; then
        local CLEN=$(cat "${FILE_HEADER}" | grep Content-Length | cut -f 2 -d " " | tr -d "\r\n")
        ## ETag (hex --> binary --> Base64)
        local ETag=$(cat "${FILE_HEADER}" | grep ETag | cut -f 2 -d " " | tr -d "\"" | xxd -r -p | base64)
        echo -e "${AWS_FEEDURL_PREFIX}${offerVersionUrl}\t${CLEN}\t${ETag}"
      fi
    done 
  done | sort >> $FILE_OUTPUT

  #gsutil cp -c $FILE_OUTPUT gs://moritani-pricebook-transferservice-sink-asia/lists/fullVersionIndexlist_sorted.txt
}
