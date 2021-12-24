#!/bin/bash -v

function setupTransfer {
    local BUCKET_TRANSFERSINK=moritani-pricebook-transferservice-sink-asia

read -r -d '' JSON > temp.json <<ENDOFJSON
    {
        "name":"test name",
        "projectId": "$(gcloud config list  --format='value(core.project)')",
        "transferSpec": {
            "httpDataSource": {
                "listUrl": "https://raw.githubusercontent.com/n0531m/awspricing2bigquery/main/artifacts/fullVersionIndexlist.tsv"
            },
            "gcsDataSink": {
                "bucketName": "${BUCKET_TRANSFERSINK}"
            }
        },
        "description": "test description",
        "status": "ENABLED",
        "schedule": {
            "scheduleStartDate": {
                "day": $(TZ=GMT date +"%-d"),
                "month": $(TZ=GMT date +"%-m"),
                "year": $(TZ=GMT date +"%-Y")
            },
            "startTimeOfDay": {
                "hours": $(TZ=GMT date +"%-H" ),
                "minutes": $(TZ=GMT date +"%-M"),
                "seconds": $(TZ=GMT date +"%-S"),
                "nanos": 0
            },
            "scheduleEndDate": {
                "day": $(TZ=GMT date +"%-d"),
                "month": $(TZ=GMT date +"%-m"),
                "year": $(TZ=GMT date +"%-Y")
            }
        }
    }
ENDOFJSON
echo $JSON | jq > temp.json
    
    #gcloud services enable storagetransfer.googleapis.com
    TOKEN=$(gcloud --project moritani-pricebook auth print-access-token)
    curl -d @temp.json \
      -H "Authorization: Bearer ${TOKEN}" \
      -H 'Content-Type: application/json' \
      -X POST https://storagetransfer.googleapis.com/v1/transferJobs 
}

