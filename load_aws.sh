#!/bin/bash 

#. ../common/common.sh

PROJECT=moritani-pricebook
PROJECT_BQ=moritani-pricebook
REGION=asia-southeast1

DATE=`date +%Y%m%d-%H%M%S`

#TABLE=billingapi_$DATE

DATADIR=./data

# create data directory if it does not exist yet.
if [ ! -d "$DATADIR" ]; then
  mkdir $DATADIR
fi

CLOUD=aws

function dumpAws {
  
  local AWS_OFFER=$1

  local TEMPDIR=$DATADIR/$CLOUD/temp
  if [ ! -d "$TEMPDIR" ]; then
    mkdir -p $TEMPDIR
  fi
  local DIR_SCHEMA=./schema

  # AWS raw data
  local AWS_FEEDURL_PREFIX=https://pricing.us-east-1.amazonaws.com
  local AWS_FEEDURL_OFFERS=$AWS_FEEDURL_PREFIX/offers/v1.0/aws/index.json

  #local AWS_OFFER=AmazonS3
  local AWS_FEEDURL=$AWS_FEEDURL_PREFIX/offers/v1.0/aws/$AWS_OFFER/current/index.json

#curl https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/index.json | jq -r -c ".offers[] | del(.currentVersionUrl) | del(.currentRegionIndexUrl)"
  local BQ_DATASET_AWS=cloud_pricing_${CLOUD}
  local BQ_DATASET_AWS_RAW=cloud_pricing_${CLOUD}_raw


  local GCS_BUCKET=moritani-pricebook-asia-southeast1
  local GCS_PATH=CloudPricing

  local FILE_SCHEMA_PRODUCTS=${DIR_SCHEMA}/$CLOUD/${AWS_OFFER}_products_schema.json
  #local FILE_SCHEMA_TERMS=./schema/$CLOUD/${AWS_OFFER}_terms_schema.json
  local FILE_SCHEMA_TERMS=${DIR_SCHEMA}/$CLOUD/aws_terms_schema.json
  

#  local FILE_VERSION=$TEMPDIR/${AWS_OFFER}_version.txt
#  echo FILE_VERSION:$FILE_VERSION

#  local DATAFILE_LOCAL=$(grep \/${AWS_OFFER}\/ < ${DATADIR}/${CLOUD}/list/currentversion.txt  | sed  's/https:\/\//\.\.\/data\/aws\/cache/g')
#  echo local DATAFILE_LOCAL=$(grep ${AWS_OFFER} < ${DATADIR}/${CLOUD}/list/currentversion.txt  | sed  's/https:\/\//\.\.\/data\/aws\/cache/g')

  local URL=$(gsutil cat gs://moritani-pricebook-transferservice-sink-asia/lists/currentversion_transfer.txt | grep $AWS_OFFER/ |  cut -f 1)
  echo URL:$URL
  #local VERSION=$(echo $URL | sed  's/https:\/\//\.\.\/data\/aws\/cache/g')
  VERSION=${URL/https:\//}
  VERSION=${VERSION%/index.json}
  VERSION=${VERSION##*/}
  #${VERSION##*/}index.json

  echo VERSION:$VERSION

  local DATAFILE_LOCAL=$TEMPDIR/${AWS_OFFER}_${VERSION}.json
  echo DATAFILE_LOCAL:$DATAFILE_LOCAL

  #echo "" >> $DATAFILE_LOCAL
  #echo $DATAFILE_LOCAL
  #file $DATAFILE_LOCAL
  #if test -e "$DATAFILE_LOCAL"
  #  then ZFLAG="-z $DATAFILE_LOCAL"
  #else ZFLAG=
  #fi
  #
  #if [ ! -e "$DATAFILE_LOCAL_PRODUCTS" ]; then
  #  #wget -c -x --directory-prefix=./data/aws/ $AWS_FEEDURL
  #  curl -o $DATAFILE_LOCAL $ZFLAG $AWS_FEEDURL 
  #fi
  if [ ! -e $DATAFILE_LOCAL ]; then
    #echo "no local file"
    #echo "url : $(grep ${AWS_OFFER} < ${DATADIR}/${CLOUD}/list/currentversion.txt)"
    #echo "local path : $DATAFILE_LOCAL"
    #echo "local dir : ${DATAFILE_LOCAL%/*}"
    if [ ! -d ${DATAFILE_LOCAL%/*} ]; then
      mkdir -p ${DATAFILE_LOCAL%/*}
    fi
    #curl $URL > $DATAFILE_LOCAL 
    DATAFILE_GCS=gs://moritani-pricebook-transferservice-sink-asia/pricing.us-east-1.amazonaws.com/offers/v1.0/aws/$AWS_OFFER/$VERSION/index.json
    DATAFILE_AWS=https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/$AWS_OFFER/$VERSION/index.json

    echo DATAFILE_GCS:$DATAFILE_GCS
    echo DATAFILE_AWS:$DATAFILE_AWS
    if [ $(gsutil -q ls $DATAFILE_GCS) ] ; then
      gsutil -o "GSUtil:parallel_process_count=1" cp -J -c $DATAFILE_GCS $DATAFILE_LOCAL
    else
      curl -c $DATAFILE_AWS > $DATAFILE_LOCAL
      gsutil -o "GSUtil:parallel_process_count=1" cp -J $DATAFILE_LOCAL $DATAFILE_GCS
    fi
    #https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonRDS/20210906192447/index.json
    #gs://moritani-pricebook-transferservice-sink-asia/pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonRDS/20210906192447/index.json

    #local DATAFILE_GCS=$(grep ${AWS_OFFER} < ${DATADIR}/${CLOUD}/list/currentversion.txt | sed 's/https:\/\//gs:\/\/moritani-pricebook-transferservice-sink-asia\//g')
    #echo "gcs path : ${DATAFILE_GCS}"
    #gsutil cp $DATAFILE_GCS ${DATAFILE_LOCAL%/*}/
  fi
  #cat $DATAFILE_LOCAL | jq -r ".version" > $FILE_VERSION
  #local VERSION=`cat $FILE_VERSION`

  local DATAFILE_LOCAL_PRODUCTS=$TEMPDIR/${AWS_OFFER}_products_${VERSION}.jsonl
#  local DATAFILE_LOCAL_PRODUCTS_DATATRANSFER=$TEMPDIR/${AWS_OFFER}_products_datatransfer_${VERSION}.jsonl
  local DATAFILE_LOCAL_TERMS=$TEMPDIR/${AWS_OFFER}_terms_${VERSION}.jsonl
  
  local DATAFILE_GCS_PRODUCTS=gs://$GCS_BUCKET/temp/${AWS_OFFER}_products_${VERSION}.jsonl
#  local DATAFILE_GCS_PRODUCTS_DATATRANSFER=gs://$GCS_BUCKET/temp/${AWS_OFFER}_products_datatransfer_${VERSION}.jsonl
  local DATAFILE_GCS_TERMS=gs://$GCS_BUCKET/temp/${AWS_OFFER}_terms_${VERSION}.jsonl

  local BQ_TABLE_PRODUCTS_RAW=$BQ_DATASET_AWS_RAW.${AWS_OFFER}_PRODUCTS_${VERSION}
#  local BQ_TABLE_PRODUCTS_DATATRANSFER_RAW=${BQ_DATASET_AWS_RAW}.${AWS_OFFER}_PRODUCTS_DATATRANSFER_${VERSION}
  local BQ_TABLE_TERMS_RAW=$BQ_DATASET_AWS_RAW.${AWS_OFFER}_TERMS_${VERSION}
  
  BQ_LOAD_OPTIONS="--max_bad_records 10000 --replace --source_format NEWLINE_DELIMITED_JSON"

   # echo  $DATAFILE_LOCAL  jq -S -c '.products[] | .sku as \$sku | .productFamily as \$productFamily | .attributes | .sku=\$sku | .productFamily=\$productFamily | select(.servicecode == ${Amazon_Offer})' 

  #cat $DATAFILE_LOCAL \
  #  | jq -S -c ".products[]  | .attributes | .servicecode " \
  #  | sort | uniq -c       
  
  if [ ! -e "$DATAFILE_LOCAL_PRODUCTS" ]; then
    echo $DATAFILE_LOCAL_PRODUCTS start
    cat $DATAFILE_LOCAL \
      | jq -S -c ".version as \$VER | .products[] | .sku as \$sku | .productFamily as \$productFamily | .attributes | .sku=\$sku | .productFamily=\$productFamily | .version=\$VER" \
      > $DATAFILE_LOCAL_PRODUCTS
    echo $DATAFILE_LOCAL_PRODUCTS end
  else
    echo $DATAFILE_LOCAL_PRODUCTS skip
  fi

  if [ ! -e " $TEMPDIR/${AWS_OFFER}_products_${VERSION}_2.jsonl" ]; then
    #echo jq -S -c ".version as \$VERSION | .products[] | .sku as \$SKU | .productFamily as \$FAMILY | {attributes:[( .attributes | to_entries[] | {key:.key, value:.value})], sku:\$SKU, productFamily:\$FAMILY, version:\$VERSION} "
    echo file : $DATAFILE_LOCAL
    cat $DATAFILE_LOCAL \
      |  jq -S -c ".version as \$VER | .products[] | .sku as \$SKU | .productFamily as \$FAMILY | {attributes:[( .attributes | to_entries[] | {key:.key, value:.value})], sku:\$SKU, productFamily:\$FAMILY, version:\$VER} " \
      >  $TEMPDIR/${AWS_OFFER}_products_${VERSION}_2.jsonl
    gsutil -o "GSUtil:parallel_process_count=1" cp -c $TEMPDIR/${AWS_OFFER}_products_${VERSION}_2.jsonl  gs://$GCS_BUCKET/temp/${AWS_OFFER}_products_${VERSION}_2.jsonl
    
    if [ -e "${DIR_SCHEMA}/aws_products_schema.json" ]; then
      #echo ${DIR_SCHEMA}/${AWS_OFFER}_products_${VERSION}_schema.json found
      bq --project_id $PROJECT_BQ load $BQ_LOAD_OPTIONS --clustering_fields sku $BQ_DATASET_AWS_RAW.${AWS_OFFER}_PRODUCTS_${VERSION}_flat gs://$GCS_BUCKET/temp/${AWS_OFFER}_products_${VERSION}_2.jsonl ${DIR_SCHEMA}/aws_products_schema.json
    else
      bq --project_id $PROJECT_BQ load $BQ_LOAD_OPTIONS --clustering_fields sku --autodetect $BQ_DATASET_AWS_RAW.${AWS_OFFER}_PRODUCTS_${VERSION}_flat gs://$GCS_BUCKET/temp/${AWS_OFFER}_products_${VERSION}_2.jsonl
      bq --project_id $PROJECT_BQ show --schema $BQ_DATASET_AWS_RAW.${AWS_OFFER}_PRODUCTS_${VERSION}_flat | jq > ${DIR_SCHEMA}/aws_products_schema.json
    fi
  fi
 
  #if [ ! -e "$DATAFILE_LOCAL_PRODUCTS_DATATRANSFER" ]; then
  #  cat $DATAFILE_LOCAL \
  #    | jq -S -c ".products[] | .sku as \$sku | .productFamily as \$productFamily | .attributes | .sku=\$sku | .productFamily=\$productFamily " \
  #    | grep '"servicecode":"AWSDataTransfer"' > ${DATAFILE_LOCAL_PRODUCTS_DATATRANSFER}
  #fi 

  if [ ! -e "$DATAFILE_LOCAL_TERMS" ]; then
    echo $DATAFILE_LOCAL_TERMS start
    cat $DATAFILE_LOCAL \
      | jq -S -c ".version as \$VER | .terms | to_entries[] | .key as \$type | .value[] | .[] | . as \$offerterm | .priceDimensions | {priceDimensions:[values[]]} | .sku=\$offerterm.sku | .offerTermCode=\$offerterm.offerTermCode | .effectiveDate=\$offerterm.effectiveDate | .termAttributes=\$offerterm.termAttributes | .type=\$type | .version=\$VER" \
      | jq -S -c --slurp "group_by(.sku)[] | {sku:(.[0].sku), terms:.} | del(.terms[].sku)" \
      | jq -S -c ".sku as \$sku | .terms[] | .sku=\$sku | if .termAttributes == {} then del(.termAttributes) else . end" \
      > ${DATAFILE_LOCAL_TERMS}
    echo $DATAFILE_LOCAL_TERMS end
  else
    echo $DATAFILE_LOCAL_TERMS skip

#    cat $DATAFILE_LOCAL \
#      | jq -S -c ".terms.Reserved | .[] | .[] | {sku:.sku,offerTermCode:.offerTermCode,effectiveDate:.effectiveDate,priceDimensions:.priceDimensions[],termAttributes:.termAttributes} | .sku as \$sku | .offerTermCode as \$offerTermCode | .effectiveDate as \$effectiveDate | .termAttributes as \$termAttributes | .priceDimensions | .sku=\$sku | .offerTermCode=\$offerTermCode | .effectiveDate=\$effectiveDate | del(.appliesTo) | .pricePerUnit_USD=.pricePerUnit.USD | del(.pricePerUnit) | .type=\"Reserved\"" \
#      >> $DATAFILE_LOCAL_TERMS
   fi 

  #wc -l $TEMPDIR/${AWS_OFFER}_*.jsonl

  
  echo file upload to GCS - start
  gsutil -o "GSUtil:parallel_process_count=1" cp -c $DATAFILE_LOCAL_PRODUCTS              $DATAFILE_GCS_PRODUCTS
  gsutil -o "GSUtil:parallel_process_count=1" cp -c $DATAFILE_LOCAL_TERMS                 $DATAFILE_GCS_TERMS

#  if [ -s $DATAFILE_LOCAL_PRODUCTS_DATATRANSFER ]; then
#    gsutil cp -c $DATAFILE_LOCAL_PRODUCTS_DATATRANSFER $DATAFILE_GCS_PRODUCTS_DATATRANSFER
#  else
#    rm $DATAFILE_LOCAL_PRODUCTS_DATATRANSFER
#  fi

  gsutil ls gs://$GCS_BUCKET/temp/${AWS_OFFER}_*_${VERSION}.jsonl
  echo file upload to GCS - end


  local BQ_DESCRIPTION="${AWS_OFFER} pricing data. version:$VERSION"

  bq --project_id $PROJECT_BQ --location ${REGION} mk -f $BQ_DATASET_AWS_RAW
  
  # load raw data for product
 # bq --project_id $PROJECT rm -f -t $BQ_TABLE_PRODUCTS_RAW
#  if [ -e "$FILE_SCHEMA_PRODUCTS" ]; then
#    bq --project_id $PROJECT load $BQ_LOAD_OPTIONS ${BQ_TABLE_PRODUCTS_RAW} ${DATAFILE_GCS_PRODUCTS} ${FILE_SCHEMA_PRODUCTS}
#  else
echo ${DIR_SCHEMA}/${AWS_OFFER}_products_${VERSION}_schema.json

 if [ -e "${DIR_SCHEMA}/${AWS_OFFER}_products_${VERSION}_schema.json" ]; then
    echo ${DIR_SCHEMA}/${AWS_OFFER}_products_${VERSION}_schema.json found
    bq --project_id $PROJECT_BQ load $BQ_LOAD_OPTIONS --clustering_fields sku ${BQ_TABLE_PRODUCTS_RAW} ${DATAFILE_GCS_PRODUCTS} ${DIR_SCHEMA}/${AWS_OFFER}_products_${VERSION}_schema.json
 elif [ -e "${DIR_SCHEMA}/${AWS_OFFER}_products_schema.json" ]; then
    echo ${DIR_SCHEMA}/${AWS_OFFER}_products_${VERSION}_schema.json found
    bq --project_id $PROJECT_BQ load $BQ_LOAD_OPTIONS --clustering_fields sku ${BQ_TABLE_PRODUCTS_RAW} ${DATAFILE_GCS_PRODUCTS} ${DIR_SCHEMA}/${AWS_OFFER}_products_schema.json
 else
    bq --project_id $PROJECT_BQ load $BQ_LOAD_OPTIONS --clustering_fields sku --autodetect ${BQ_TABLE_PRODUCTS_RAW} ${DATAFILE_GCS_PRODUCTS}
    bq --project_id $PROJECT_BQ show --schema ${BQ_TABLE_PRODUCTS_RAW} | jq > ${DIR_SCHEMA}/${AWS_OFFER}_products_${VERSION}_schema.json
 fi

bq --project_id $PROJECT_BQ update --description "${BQ_DESCRIPTION}" ${BQ_TABLE_PRODUCTS_RAW}

#  if [ -e "$DATAFILE_LOCAL_PRODUCTS_DATATRANSFER" ]; then
#    bq --project_id $PROJECT load $BQ_LOAD_OPTIONS --autodetect ${BQ_TABLE_PRODUCTS_DATATRANSFER_RAW} ${DATAFILE_GCS_PRODUCTS_DATATRANSFER}
#  fi

echo ${DIR_SCHEMA}/${AWS_OFFER}_terms_${VERSION}_schema.json

#  bq --project_id $PROJECT_BQ rm -f -t $BQ_TABLE_TERMS_RAW

SCHEMA_TERMS=${DIR_SCHEMA}/aws_terms_schema.json
# load raw data for pricing 
if [ -e "${SCHEMA_TERMS}" ]; then
  echo ${SCHEMA_TERMS} found
  bq --project_id $PROJECT_BQ load $BQ_LOAD_OPTIONS --clustering_fields sku ${BQ_TABLE_TERMS_RAW} ${DATAFILE_GCS_TERMS} ${SCHEMA_TERMS}

else
  bq --project_id $PROJECT_BQ load $BQ_LOAD_OPTIONS --clustering_fields sku --autodetect ${BQ_TABLE_TERMS_RAW} ${DATAFILE_GCS_TERMS}
  bq --project_id $PROJECT_BQ show --schema ${BQ_TABLE_TERMS_RAW} | jq > ${SCHEMA_TERMS}

fi
#  if [ -e "$FILE_SCHEMA_TERMS" ]; then
#    bq --project_id $PROJECT load $BQ_LOAD_OPTIONS ${BQ_TABLE_TERMS_RAW} ${DATAFILE_GCS_TERMS} ${FILE_SCHEMA_TERMS}
#  else
#  fi
  bq --project_id $PROJECT_BQ update --description "${BQ_DESCRIPTION}" ${BQ_TABLE_TERMS_RAW}

  bq --project_id $PROJECT_BQ --location ${REGION} mk -f $BQ_DATASET_AWS 
  # load table and view for AWS_EC2
  #create_bq_table_and_view_from_sql ${BQ_TABLE_EC2_VM} ${BQ_TABLE_EC2_VM_VIEW} "${SQL_EC2}" ./sql/ec2.sql ${DIR_LOG}/bq_ec2_table.log ${DIR_LOG}/bq_ec2_view.log  "$GCP_DESCRIPTION" 

}

function create_bq_table_and_view_from_sql {
  local _bq_table=$1
  local _bq_view=$2
  local _sql=$3
  local _sql_out=$4
  local _table_log=$5
  local _view_log=$6
  local DESCRIPTION=$7

  # store sql for reference
  echo "${_sql}" > ${_sql_out}
  

  # delete table before loading query result
  bq --project_id $PROJECT rm -f -t ${_bq_table}
  bq --project_id $PROJECT query --nouse_legacy_sql --replace --destination_table ${_bq_table} "${_sql}" > ${_table_log}
  bq --project_id $PROJECT update --description "${DESCRIPTION}" ${_bq_table}

  # delete table before loading query result
  bq --project_id $PROJECT rm -f -t ${_bq_view}
  bq --project_id $PROJECT mk --view="${_sql}" --nouse_legacy_sql --description "${DESCRIPTION}  ---\n  ${_sql}" ${_bq_view} > "${_view_log}"
}





function downloadAwsPricing {
  AWS_OFFER=$1
  local AWS_FEEDURL_PREFIX=https://pricing.us-east-1.amazonaws.com
  #AWS_OFFER=AmazonKinesisFirehose
  local versionIndexUrl=$(curl -s $AWS_FEEDURL_PREFIX/offers/v1.0/aws/index.json \
   | jq --arg offer $AWS_OFFER -r ".offers | .[\$offer] | .versionIndexUrl")
  echo $AWS_FEEDURL_PREFIX$versionIndexUrl
  local offerVersionUrl=$(curl -s $AWS_FEEDURL_PREFIX$versionIndexUrl | jq -r '[.versions[]] | sort_by(.offerVersionUrl)[-1].offerVersionUrl')
  echo $AWS_FEEDURL_PREFIX$offerVersionUrl
  VERSION=${offerVersionUrl%/index.json}
  VERSION=${VERSION##*/}
  #${VERSION##*/}index.json
  echo $VERSION
  
  local DIR_DOWNLOAD=$DATADIR/$CLOUD/downloaded
  local FILE_DOWNLOAD=$DIR_DOWNLOAD/${AWS_OFFER}_${VERSION}.json
  #echo ${AWS_FEEDURL_PREFIX}${offerVersionUrl}
  echo $FILE_DOWNLOAD
  wget -q -O $FILE_DOWNLOAD -c ${AWS_FEEDURL_PREFIX}${offerVersionUrl}
}
function downloadAll {
  for AWS_OFFER in $(curl https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/index.json | jq -r '.offers[] | .offerCode' | sort)
  do 
    downloadAwsPricing $AWS_OFFER
  done
}
function aws_all {
  for AWS_OFFER in $(curl https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/index.json | jq -r '.offers[] | .offerCode' | sort)
  do 
    dumpAws ${AWS_OFFER}
  done
}

function cleanup {
  for i in  $(find ./indexes -type f | grep current) ; do rm $i ; done 
  for i in  $(find ./indexes -type d | grep current) ; do rm -rf $i ; done 
}
function awsUrlToLocalPath {
  local AWS_HOST=pricing.us-east-1.amazonaws.com
  local LOCAL_DIR=./indexes
  local AWS_URL=$1

  echo $LOCAL_DIR/${AWS_URL#https://}
}
function awsPathToGCSPath {
  local AWS_URL=$1
  local GCS_FOLDERPATH=$2

  echo ${GCS_FOLDERPATH}/${AWS_URL#https://}
}
function cpAwsJsonToGCS {
  local AWS_URL=$1
  local GCS_FOLDERPATH=$2
  curl -s $AWS_URL | gsutil cp -c -J - ${GCS_FOLDERPATH}/${AWS_URL#https://}
}
#dumpAws $1
#aws_all

#createAwsVersionIndexDownloadlist
#createAwsCurrentVersionsDownloadlist
#createAwsFullVersionIndexDownloadlist
#createAwsFullVersionIndexDownloadlist

#awsUrlToLocalPath https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AWSDataSync/index.json

#cpAwsJsonToGCS https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEC2/20190828220000/index.json gs://moritani-pricebook-transferservice-sink-asia

#gs://moritani-pricebook-transferservice-sink-asia/pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEC2/20210831222446/index.json