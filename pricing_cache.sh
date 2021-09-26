#!/bin/bash -v

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
function cacheRefreshMasterIndex {
    cacheAndValidate "${AWS_FEEDURL_INDEX}"
}
export -f cacheRefreshMasterIndex

function cacheContentByUrl {
    local URL=$1
    local FILE=${DIR_CACHE}/${URL#https://}
    #echo cacheContentByUrl $URL
    #echo cacheContentByUrl $FILE
    
    wget -N -q -P "${DIR_CACHE}" -x "${URL}" && echo "${URL} : cached"
    #curl -s --output-dir ${DIR_CACHE} --create-dirs -o ${URL#https://} $URL && echo "${URL} : cached"
    #  curl -s -C - --output-dir ${DIR_CACHE} --create-dirs -o ${URL#https://} $URL && echo "${URL} : cached"
    if [ ! -s "${FILE}" ] ; then
        sleep 2;  wget -N -q -P "${DIR_CACHE}" -x "${URL}" && echo "${URL} : cached"
        #sleep 2;  curl -s --output-dir ${DIR_CACHE} --create-dirs -o ${URL#https://} $URL && echo "${URL} : cached"
        if [ ! -s "${FILE}" ] ; then
            echo "failed to fetch header for $URL"
        fi
    fi
}
export -f cacheContentByUrl

function cacheHeaderByUrl {
    local URL=$1
    local FILE_HEADER=${DIR_HEADERS}/${URL#https://}
    
    local FILE_HEADER_DIR=${FILE_HEADER%/*}
    
    if [ ! -d "${FILE_HEADER_DIR}" ] ; then mkdir -p "${FILE_HEADER_DIR}" ; fi
    
    curl -s -I "$URL" > "${FILE_HEADER}"
    if [ ! -s "${FILE_HEADER}" ] ; then
        sleep 2;  curl -s -I "$URL" > "${FILE_HEADER}"
        if [ ! -s "${FILE_HEADER}" ] ; then
            sleep 4;  curl -s -I "$URL" > "${FILE_HEADER}"
            if [ ! -s "${FILE_HEADER}" ] ; then
                echo "failed to fetch header for $URL"
            fi
        fi
    fi
}
export -f cacheHeaderByUrl

## capture index file
function pullAwsVersionIndexes {
    
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
    
}

function pullAwsVersionIndexesFull {
    
    cacheAndValidate "${AWS_FEEDURL_INDEX}"
    
    for INDEXPATH in $(cat "$LOCAL_INDEX" | jq -r '.offers[] | .versionIndexUrl , .savingsPlanVersionIndexUrl , .currentRegionIndexUrl, .currentSavingsPlanIndexUrl' | grep -v null | sort | uniq)
    do
        echo "${AWS_FEEDURL_PREFIX}${INDEXPATH}"
        #echo ${AWS_FEEDURL_PREFIX}${INDEXPATH} >&2
    done | xargs -n 2 -P 0 -I {} bash -c "cacheAndValidate {}"
}


function cacheAndValidate {
    local URL=$1
    #echo \#downloadAndValidateUrl ${URL}
    
    local FILE=${DIR_CACHE}/${URL#https://}
    #  echo cacheAndValidate FILE:${FILE}
    
    local FILE_HEADER=${DIR_HEADERS}/${URL#https://}
    #echo cacheAndValidate FILE_HEADER:${FILE_HEADER}
    
    ## fetch header with exponential backoff
    cacheHeaderByUrl "${URL}"

    if [ ! -s "${FILE_HEADER}" ] ; then
        echo "failed to fetch header for $URL" >&2 
        echo "cannot validate with empty header $FILE_HEADER" >&2
        return
    else
        
      local CLEN=$(cat "${FILE_HEADER}" | grep Content-Length | cut -f 2 -d " " | tr -d "\r\n")
      #echo header.Content-Length : $CLEN
      local ETag=$(cat "${FILE_HEADER}" | grep ETag | cut -f 2 -d " " | tr -d "\"\r\n") # | xxd -r -p | base64
      #echo header.ETag : $ETag

      if [ ! -f $FILE ] ; then
        cacheContentByUrl "${URL}"
      fi

      if [ -f $FILE ] ; then
        local size=$(stat -f "%z" "$FILE")
        local local_md5=$(md5 -q "$FILE" | tr -d "\"\r\n")

        if [[ ! $size -eq ${CLEN} ]] ; then
          echo "cacheAndValidate : file size does not match expected. actual : $size , expected : $CLEN. re-download" >&2
          echo "${URL}" >&2
          rm "$FILE"
          cacheContentByUrl "${URL}"
          elif [[ ! ${local_md5} == ${ETag} ]] ; then
          echo "cacheAndValidate : file md5 hash does not match ETag. actual : ${local_md5}, expected : ${ETag}. re-download" >&2
          echo "${URL}" >&2
          #curl -I ${URL}
          rm "$FILE"
          cacheContentByUrl "${URL}"
        fi
      fi
  fi
}
export -f cacheAndValidate

## capture index file
function pullCurrentOffers {
    cacheRefreshMasterIndex
    
    ## for each service, download their own version index file
    cat "$LOCAL_INDEX" \
    | jq -r --arg prefix ${AWS_FEEDURL_PREFIX} '.offers[] | $prefix+"/offers/v1.0/aws/"+.offerCode+"/current/index.json"' \
    | xargs -n 2 -P 0 -I {}  bash -c "cacheAndValidate {}"
}

function pullLatestOffers {
    
    cacheRefreshMasterIndex
    
    ## for each service, download their own version index file
    cat "$LOCAL_INDEX" \
    | jq -r --arg prefix "${DIR_CACHE}/${AWS_FEEDURL_PREFIX#https://}" '.offers[] | $prefix+"/offers/v1.0/aws/"+.offerCode+"/index.json"' \
    | xargs -n 2 -P 0 -I {}  cat {} | jq -r  --arg prefix "${AWS_FEEDURL_PREFIX}" '.currentVersion as $ver | .versions[$ver] | $prefix+.offerVersionUrl' \
    | xargs -n 2 -P 0 -I {} bash -c "cacheAndValidate {}"
}

function pullAwsOfferVersion {
    local AWS_OFFER=$1
    local VERSION=current
    if [[ "$#" == 0 ]]; then
        echo "pullAwsOfferVersion : Illegal number ($#) of parameters" ; return
        elif [[ "$#" == 2 ]]; then
        VERSION=$2
        elif [[ "$#" -gt 2 ]]; then
        echo "pullAwsOfferVersion : Illegal number (\"$#\") of parameters" ; return
    fi
    cacheAndValidate "${AWS_FEEDURL_PREFIX}/offers/v1.0/aws/${AWS_OFFER}/${VERSION}/index.json"
}
export -f pullAwsOfferVersion

function listAwsOfferVersions {
  local AWS_OFFER=$1
  if [[ "$#" != 1 ]]; then
    echo "listAwsOfferVersions : Illegal number ($#) of parameters"
    echo -e "\tusage : listAwsOfferVersions <AWS_OFFER>" ; return
  fi
  cacheRefreshMasterIndex

  URL_OFFERINDEX=${AWS_FEEDURL_PREFIX}/offers/v1.0/aws/${AWS_OFFER}/index.json
  cacheAndValidate $URL_OFFERINDEX

  FILE_OFFERINDEX=${DIR_CACHE}/${URL_OFFERINDEX#https://}
  
  jq -r '.versions | keys[] ' < "$FILE_OFFERINDEX" | sort
}

function pullAwsOfferAllVersions {
  local AWS_OFFER=$1
  cacheRefreshMasterIndex

  URL_OFFERINDEX=${AWS_FEEDURL_PREFIX}/offers/v1.0/aws/${AWS_OFFER}/index.json
  FILE_OFFERINDEX=${DIR_CACHE}/${URL_OFFERINDEX#https://}
  #echo $URL_OFFERINDEX
  #echo $FILE_OFFERINDEX
  
  cacheAndValidate $URL_OFFERINDEX

  if [ -f "$FILE_OFFERINDEX" ] ; then
#    jq -r \
#      --arg prefix "${AWS_FEEDURL_PREFIX}" \
#      --arg offer "${AWS_OFFER}" \
#      '.versions | keys[] | [$prefix+"/offers/v1.0/aws/"+$offer+"/"+.+"/index.json",$prefix+"/offers/v1.0/aws/"+$offer+"/"+.+"/region_index.json"] | .[]' \
#    < "$FILE_OFFERINDEX" \
#    | xargs -n 2 -P 0 -I {} bash -c "cacheAndValidate {}"


#     jq -r '.versions | keys[] ' < "$FILE_OFFERINDEX" \
#      | xargs -n 2 -P 0 -I {} echo ${AWS_FEEDURL_PREFIX}/offers/v1.0/aws/${AWS_OFFER}/{}/region_index.json \
#      | xargs -n 2 -P 0 -I {} curl -s {} \
#      | jq -r '.regions[].currentVersionUrl'  \
#      | xargs -n 2 -P 0 -I {} echo ${AWS_FEEDURL_PREFIX}{} \
#      | xargs -n 2 -P 0 -I {} bash -c "cacheAndValidate {}"

     jq -r '.versions | keys[] ' < "$FILE_OFFERINDEX" \
      | xargs -n 2 -P 0 -I {} echo ${AWS_FEEDURL_PREFIX}/offers/v1.0/aws/${AWS_OFFER}/{}/index.json \
      | xargs -n 2 -P 0 -I {} bash -c "cacheAndValidate {}" 

     jq -r '.versions | keys[] ' < "$FILE_OFFERINDEX" \
      | xargs -n 2 -P 0 -I {} echo ${AWS_FEEDURL_PREFIX}/offers/v1.0/aws/${AWS_OFFER}/{}/region_index.json \
      | xargs -n 2 -P 0 -I {} bash -c "cacheAndValidate {}" 

     find ${DIR_CACHE}/${AWS_FEEDURL_PREFIX#https://}/offers/v1.0/aws/${AWS_OFFER} -name region_index.json \
      | xargs -n 2 -P 0 -I {} cat {} \
      | jq -r --arg prefix "${AWS_FEEDURL_PREFIX}" '.regions[] | $prefix+.currentVersionUrl' \
      | xargs -n 2 -P 0 -I {} bash -c "cacheAndValidate {}" 

#   
  fi

}



function pushAwsCache2GCS {
    gsutil -m -o GSUtil:parallel_process_count=1 rsync -r -J "${DIR_CACHE}" "gs://${BUCKET_STS_SINK}/"
}
