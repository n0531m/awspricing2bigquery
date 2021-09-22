#!/bin/bash -v

## aws feeds will be cached in local directory $DIR_CACHE
## url structure of all feeds are preserved so that I don't have to think of unique file names


function clearCache {
  if [ -d "${DIR_CACHE}" ] ; then 
    rm -rf ${DIR_CACHE}/*
  fi
}
function clearHeaders {
  if [ -d "${DIR_HEADERS}" ] ; then 
    rm -rf ${DIR_HEADERS}/*
  fi
}
function cacheRefreshMasterIndex {
  cacheAndValidate ${AWS_FEEDURL_INDEX}
}
export -f cacheRefreshMasterIndex

function cacheContentByUrl {
  local URL=$1
  local FILE=${DIR_CACHE}/${URL#https://}
  #echo cacheContentByUrl $URL
  #echo cacheContentByUrl $FILE
  #wget -q -P ${DIR_CACHE} -x ${URL} && echo "${URL} : cached
  
  curl -s -C - --output-dir ${DIR_CACHE} --create-dirs -o ${URL#https://} $URL && echo "${URL} : cached"
}
export -f cacheContentByUrl

function cacheHeaderByUrl {
  local URL=$1
  local FILE_HEADER=${DIR_HEADERS}/${URL#https://}
 
  local FILE_HEADER_DIR=${FILE_HEADER%/*}

  if [ ! -d "${FILE_HEADER_DIR}" ] ; then mkdir -p "${FILE_HEADER_DIR}" ; fi
  curl -s -I $URL > ${FILE_HEADER}
}
export -f cacheHeaderByUrl

## capture index file 
function refreshAwsVersionIndexes {
  
  cacheRefreshMasterIndex
  
  ## for each service, download their own version index file
  for AWS_OFFER in $(cat "${LOCAL_INDEX}" | jq -r '.offers[] | .offerCode' | sort)
  do 
    #echo "${AWS_FEEDURL_PREFIX}/offers/v1.0/aws/${AWS_OFFER}/index.json" >&2
    echo "${AWS_FEEDURL_PREFIX}/offers/v1.0/aws/${AWS_OFFER}/index.json"
  done | xargs -n 2 -P 0 -I {} bash -c "cacheAndValidate {}"
  #wget -c -q -P ${DIR_CACHE} -c -x
}


function pullAwsSavingsPlanVersionIndexes {
#  local DIR_CACHE=./cache

#  local AWS_FEEDURL_PREFIX=https://pricing.us-east-1.amazonaws.com

  local OFFERS=("AWSComputeSavingsPlan" "AWSMachineLearningSavingsPlans")

  for OFFER in "${OFFERS[@]}"
  do
    echo "${AWS_FEEDURL_PREFIX}/savingsPlan/v1.0/aws/${OFFER}/current/index.json"
    echo "${AWS_FEEDURL_PREFIX}/savingsPlan/v1.0/aws/${OFFER}/current/region_index.json"
    for VERSIONURL in $(curl -s "${AWS_FEEDURL_PREFIX}/savingsPlan/v1.0/aws/${OFFER}/current/index.json" | jq -r '.versions[].offerVersionUrl' | sort -r | head -1) 
    do
      echo "${AWS_FEEDURL_PREFIX}${VERSIONURL}"
      for REGIONVERSIONURL in $(curl -s "${AWS_FEEDURL_PREFIX}${VERSIONURL}" | jq -r '.regions[] | select(.regionCode == "ap-southeast-1") | .versionUrl') 
      do
        echo "${AWS_FEEDURL_PREFIX}${REGIONVERSIONURL}"
      done
    done
  done | xargs -n 2 -P 0 -I {} bash -c "cacheAndValidate {}"
  #| xargs -n 2 -P 0 wget -q -P ${DIR_CACHE} -c -x

}

function pullAwsVersionIndexesFull {

  cacheAndValidate ${AWS_FEEDURL_INDEX}

  for INDEXPATH in $(cat $LOCAL_INDEX | jq -r '.offers[] | .versionIndexUrl , .savingsPlanVersionIndexUrl , .currentRegionIndexUrl, .currentSavingsPlanIndexUrl' | grep -v null | sort | uniq)
  do 
    echo ${AWS_FEEDURL_PREFIX}${INDEXPATH}
    #echo ${AWS_FEEDURL_PREFIX}${INDEXPATH} >&2
  done | xargs -n 2 -P 0 -I {} bash -c "cacheAndValidate {}"
}


function cacheAndValidate {
  local URL=$1
  #echo \#downloadAndValidateUrl ${URL}
#  local DIR_HEADER=./header
#  local DIR_CACHE=./cache

#  if [ ! -d ${DIR_HEADER} ] ; then mkdir -p ${DIR_HEADER} ; fi
    echo cacheAndValidate URL:${URL}

  local FILE=${DIR_CACHE}/${URL#https://}
    echo cacheAndValidate FILE:${FILE}

  local FILE_HEADER=${DIR_HEADERS}/${URL#https://}
  echo cacheAndValidate FILE_HEADER:${FILE_HEADER}
  #FILE_HEADER=${FILE_HEADER%/.*}.txt

#  local FILE_HEADER_DIR=${FILE_HEADER%/*}
#  if [ ! -d ${FILE_HEADER_DIR} ] ; then mkdir -p ${FILE_HEADER_DIR} ; fi


  ## fetch header with exponential backoff
  cacheHeaderByUrl "${URL}" 
  if [ ! -s "${FILE_HEADER}" ] ; then 
    sleep 2 ;  cacheHeaderByUrl "${URL}"
    if [ ! -s "${FILE_HEADER}" ] ; then 
      sleep 4 ; cacheHeaderByUrl "${URL}"
      if [ ! -s "${FILE_HEADER}" ] ; then 
        sleep 8 ; cacheHeaderByUrl "${URL}"
        if [ ! -s "${FILE_HEADER}" ] ; then 
           echo "failed to fetch header for $URL"
           echo "cannot validate with empty header $FILE_HEADER"
        fi
      fi
    fi
  fi

  if [ ! -s "${FILE_HEADER}" ] ; then echo cannot validate with empty "${FILE_HEADER}" ; fi

  local CLEN=$(cat "${FILE_HEADER}" | grep Content-Length | cut -f 2 -d " " | tr -d "\r\n")
  #echo header.Content-Length : $CLEN
  local ETag=$(cat "${FILE_HEADER}" | grep ETag | cut -f 2 -d " " | tr -d "\"\r\n") # | xxd -r -p | base64
  #echo header.ETag : $ETag
    
  if [ ! -f $FILE ] ; then
    #echo $FILE does not exist
    #wget -q -P ${DIR_CACHE} -x ${URL}  && echo ${URL} cached
    cacheContentByUrl "${URL}"
    #echo $FILE
    local size=$(stat -f "%z" $FILE)
    #echo size:$size
    local local_md5=$(md5 -q $FILE | tr -d "\"\r\n")
    #echo local_md5:$local_md5    
    if [ ! $size -eq ${CLEN} ] ; then
      rm $FILE ; echo file size does not match. deleting fetched file $FILE
    elif [[ ! ${local_md5} == ${ETag} ]] ; then
      rm $FILE ; echo file md5 hash does not match. deleting fetched file $FILE
    fi

  else
    #echo $FILE already exist
    local size=$(stat -f "%z" $FILE)
    local local_md5=$(md5 -q $FILE | tr -d "\"\r\n")
    
    if [[ ! $size -eq ${CLEN} ]] ; then
      echo "file size does not match re-download. actual : $size , expected : $CLEN"
      echo ${URL}
      echo ${FILE_HEADER}
      cacheContentByUrl "${URL}"
    elif [[ ! ${local_md5} == ${ETag} ]] ; then
      echo "file md5 hash does not match ETag. re-download"
      echo ${URL}
      cacheContentByUrl "${URL}"
    fi
  fi
}
export -f cacheAndValidate

## capture index file 
function pullAwsCurrents {

  refreshMasterIndex

  ## for each service, download their own version index file
  for AWS_OFFER in $(cat $LOCAL_INDEX | jq -r '.offers[] | .offerCode' | sort)
  do 
    echo ${AWS_FEEDURL_PREFIX}/offers/v1.0/aws/${AWS_OFFER}/current/index.json
  done | xargs -n 2 -P 0 -I {} bash -c "cacheAndValidate {}"
}

function pullAwsOfferCurrent {
  local AWS_OFFER=$1
  pullAwsOfferVersion ${AWS_OFFER} current
}
function pullAwsOfferVersion {
  local AWS_OFFER=$1
  local VERSION=$2
  if [[ "$#" != 2 ]]; then
    echo "pullAwsOfferVersion : Illegal number of parameters"; return
  fi
  cacheAndValidate "${AWS_FEEDURL_PREFIX}/offers/v1.0/aws/${AWS_OFFER}/${VERSION}/index.json"
}


function pullAwsLatests {

  refreshMasterIndex
  
  ## for each service, download their own version index file
  
  for AWS_OFFER in $(cat $LOCAL_INDEX | jq -r  '.offers[] | .offerCode' | sort)
  do 
    local VERSIONINDEX_URL=${AWS_FEEDURL_PREFIX}/offers/v1.0/aws/${AWS_OFFER}/index.json
    local VERSIONINDEX_LOCAL=${DIR_CACHE}/${VERSIONINDEX_URL#https://}
    #echo $VERSIONINDEX_LOCAL >&2
    cat $VERSIONINDEX_LOCAL | jq -r --arg prefix "$AWS_FEEDURL_PREFIX" '.versions[] | $prefix + .offerVersionUrl' | sort -r | head -n 1
  done | xargs -n 2 -P 0 -I {} bash -c "cacheAndValidate {}"
  #wget -q -P ${DIR_CACHE} -c -x
}

function pushAwsCache2GCS {
  gsutil -m -o GSUtil:parallel_process_count=1 rsync -r -J ./cache gs://moritani-pricebook-transferservice-sink-asia/
}
