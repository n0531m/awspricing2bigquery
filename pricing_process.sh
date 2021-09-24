#!/bin/bash -v

function preprocessOfferdata {
    local AWS_OFFER=$1
    local VERSION=$2
    if [[ "$#" != 2 ]]; then
      echo "preprocessOfferdata : Illegal number of parameters"; return
    fi
    local OFFERVERSION_AWS=${AWS_FEEDURL_PREFIX}/offers/v1.0/aws/$AWS_OFFER/$VERSION/index.json
    local OFFERVERSION_LOCAL=${DIR_CACHE}/${OFFERVERSION_AWS#https://}
    local OFFERVERSION_PROCESSED=${DIR_PROCESSED}/${OFFERVERSION_AWS#https://}
    local OFFERVERSION_PROCESSED_DIR=${OFFERVERSION_PROCESSED%/*}

    echo "OFFERVERSION_AWS   : $OFFERVERSION_AWS"
    echo "OFFERVERSION_LOCAL : $OFFERVERSION_LOCAL"
    #echo "OFFERVERSION_LOCAL_DIR : $OFFERVERSION_LOCAL_DIR"
    echo "OFFERVERSION_PROCSSED_DIR : $OFFERVERSION_PROCESSED_DIR"

    if [ ! -d "$OFFERVERSION_PROCESSED_DIR" ] ; then mkdir -p "$OFFERVERSION_PROCESSED_DIR" ; fi

    VERSION=$(cat "$OFFERVERSION_LOCAL" | jq -e -r .version ) || echo jq error "$OFFERVERSION_LOCAL"

    if [ ! -e $$OFFERVERSION_LOCAL ]; then
        
        if [ ! -f "${OFFERVERSION_PROCESSED_DIR}/products2.jsonl" ]; then
          cat "$OFFERVERSION_LOCAL" \
              | jq -S -c ".version as \$VER | .products[] | .version=\$VER | .usagetype=.attributes.usagetype | .servicecode=.attributes.servicecode | .servicename=.attributes.servicename |  .location=.attributes.location |  .locationType=.attributes.locationType| del(.attributes.servicename, .attributes.servicecode, .attributes.usagetype, .attributes.location, .attributes.locationType) | .attributes=[(.attributes | to_entries[] | {key:.key, value:.value})] " \
              > "${OFFERVERSION_PROCESSED_DIR}/products2.jsonl"
        fi

        if [ ! -f "${OFFERVERSION_PROCESSED_DIR}/terms2.jsonl" ]; then
          cat "$OFFERVERSION_LOCAL" \
              | jq -S -c ".version as \$VER | .terms | to_entries[] | .key as \$type | .value[][] | .termAttributes=[(.termAttributes | to_entries[] | {key:.key, value:.value})] | .priceDimensions=[.priceDimensions[]] | .type=\$type | .version=\$VER " \
              > "${OFFERVERSION_PROCESSED_DIR}/terms2.jsonl"
        fi
    fi
}
export -f preprocessOfferdata

function _concatFiles {
  
  if [ ! -d $DIR_OUT_CONCAT ]; then mkdir -p ${DIR_OUT_CONCAT} ; fi

    for FILE in $(find ${DIR_PROCESSED}/pricing.us-east-1.amazonaws.com/offers/v1.0/aws -name products2.jsonl | sort)
    do 
      cat "${FILE}"
    done > ${DIR_OUT_CONCAT}/aws_products.jsonl
  
    for FILE in $(find ${DIR_PROCESSED}/pricing.us-east-1.amazonaws.com/offers/v1.0/aws -name terms2.jsonl | sort)
    do 
      cat "${FILE}"
    done > ${DIR_OUT_CONCAT}/aws_terms.jsonl
}
function _concatOfferFiles {
  local AWS_OFFER=$1
  
  if [ ! -d "$DIR_OUT_CONCAT" ]; then mkdir -p "${DIR_OUT_CONCAT}" ; fi

  for FILE in $(find ${DIR_PROCESSED}/pricing.us-east-1.amazonaws.com/offers/v1.0/aws/${AWS_OFFER} -name products2.jsonl | sort)
  do 
    cat "${FILE}"
  done > ${DIR_OUT_CONCAT}/aws_products.jsonl

  for FILE in $(find ${DIR_PROCESSED}/pricing.us-east-1.amazonaws.com/offers/v1.0/aws/${AWS_OFFER} -name terms2.jsonl | sort)
  do 
    cat "${FILE}"
  done > ${DIR_OUT_CONCAT}/aws_terms.jsonl
}

function processAndLoadOfferVersion {
  local AWS_OFFER=$1
  local VERSION=current

  if [[ "$#" == 0 ]]; then
     echo "processAndLoadOfferVersion : Illegal number ($#) of parameters" ; return
  elif [[ "$#" == 2 ]]; then
      VERSION=$2
  elif [[ "$#" -gt 2 ]]; then
      echo "processAndLoadOfferVersion : Illegal number ($#) of parameters" ; return
  fi
  #if [[ "$#" != 2 ]]; then
  #  echo "processAndLoadOfferVersion : Illegal number of parameters"; return
  #fi

  pullAwsOfferVersion $AWS_OFFER $VERSION
  preprocessOfferdata $AWS_OFFER $VERSION
  _concatOfferFiles $AWS_OFFER
  _load2BqStaging
  mergestaging2main
}


function processAndLoadCurrentAll {
  if [ ! -f "${LOCAL_INDEX}" ] ; then (echo "$LOCAL_INDEX does not exist" ; return) ; fi
  jq -r '.offers[] | .offerCode' < "$LOCAL_INDEX" \
    | xargs -n 2 -P 0 -I {} bash -c "preprocessOfferdata {} current"
  _concatFiles
  _load2BqStaging
  mergestaging2main
}

function _load2BqStaging {

  bq --project_id ${BQ_PROJECT} show ${BQ_DATASET_STAGING} \
    || bq --project_id ${BQ_PROJECT} mk -d --data_location ${REGION} ${BQ_DATASET_STAGING}


  ### upload files to GCS 
  local GCS_PATH=gs://${BUCKET_WORK}/processed/concat
  local GCS_PATH_PRODUCTS=${GCS_PATH}/aws_products.jsonl
  local GCS_PATH_TERMS=${GCS_PATH}/aws_terms.jsonl
  
  gsutil -m -o GSUtil:parallel_process_count=1 rsync -r -J ${DIR_OUT_CONCAT} ${GCS_PATH}


  ### load products/terms into a BigQuery table each

  local SCHEMA_PRODUCTS=${DIR_SCHEMA}/aws_products_schema2.json
  local SCHEMA_TERMS=${DIR_SCHEMA}/aws_terms_schema2.json
  local TABLE_PRODUCTS=${BQ_DATASET_STAGING}.${BQ_TABLE_PREFIX}_products
  local TABLE_TERMS=${BQ_DATASET_STAGING}.${BQ_TABLE_PREFIX}_terms

  local BQ_LOAD_OPTIONS="--max_bad_records 10000 --replace --source_format NEWLINE_DELIMITED_JSON"

  bq --project_id ${BQ_PROJECT} load ${BQ_LOAD_OPTIONS} --clustering_fields sku ${TABLE_PRODUCTS} ${GCS_PATH_PRODUCTS} ${SCHEMA_PRODUCTS}
  bq --project_id ${BQ_PROJECT} load ${BQ_LOAD_OPTIONS} --clustering_fields sku ${TABLE_TERMS}    ${GCS_PATH_TERMS}    ${SCHEMA_TERMS}


  ### joining the terms table and product table into a single offer table

  local FILE_SQL=${DIR_SQL}/aws_offer_join_terms_and_products.sql
  cat > ${FILE_SQL} <<- EOF
    CREATE OR REPLACE TABLE \`${BQ_PROJECT}.${BQ_DATASET_STAGING}.${BQ_TABLE_PREFIX}\`
    CLUSTER BY sku, version AS (
      SELECT *  
      FROM      \`${BQ_PROJECT}.${BQ_DATASET_STAGING}.${BQ_TABLE_PREFIX}_terms\`
      LEFT JOIN \`${BQ_PROJECT}.${BQ_DATASET_STAGING}.${BQ_TABLE_PREFIX}_products\`
      USING (sku, version) 
    )
EOF
  cat ${FILE_SQL} | bq --project_id ${BQ_PROJECT} query --nouse_legacy_sql
}

function mergestaging2main {

  local FILE_SQL=${DIR_SQL}/aws_offer_merge.sql
  cat > ${FILE_SQL} <<- EOF
    MERGE INTO \`${BQ_PROJECT}.${BQ_DATASET}.${BQ_TABLE_PREFIX}\` T
    USING \`${BQ_PROJECT}.${BQ_DATASET_STAGING}.${BQ_TABLE_PREFIX}\` S
    ON  T.sku = S.sku
    AND T.version = S.version
    and T.offerTermCode=S.offerTermCode

    WHEN NOT MATCHED BY TARGET THEN INSERT ROW
EOF
  cat "${FILE_SQL}" | bq --project_id "${BQ_PROJECT}" query --nouse_legacy_sql
}

function createOfferTable {
  bq --project_id ${BQ_PROJECT} \
    --dataset_id=${BQ_DATASET} \
    mk --table \
    --description "AWS Pricing table. combined key : sku,version,offerTermCode" \
    --label owner:moritani \
    --label cloud:aws \
    ${BQ_TABLE_PREFIX} \
    ${DIR_SCHEMA}/aws_offer_schema.json
}
function recreateOfferTable {
  bq --project_id ${BQ_PROJECT} \
    rm -f ${BQ_DATASET}.${BQ_TABLE_PREFIX}
  createOfferTable
}
