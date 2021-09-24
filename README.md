## this project

AWS pricing details are available through AWS Price List API (query API, bulk API), but in many cases you want to slice and dice this further.

* [Using the AWS Price List API](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/price-changes.html)
  * [Using the query API](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/using-pelong.html)
  * [Using the bulk API](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/using-ppslong.html)

Personally, my platform of choice for everything data is GCP. So will automate the processing of onboarding the data aiming to *"organize ~~the world's~~ **AWS pricing** information and make it universally accessible and useful"*

Given the nature of use cases in mind (not much details to be shared here), the end state will be to have the data all in Google Cloud's [BigQuery](https://cloud.google.com/bigquery) as a starting point, although not limited to.

## high level approach

will have the following building blocks

* Download offer data from AWS's API
  * Will also make data aquisition automated, so that I don't have to always hit AWS's endpoint, and also make it easy for downstream consumption.
* Reshaping of the data
  * The offer json files look like a dump from a document store, and unusable for analytics. so will turn it into something more useful
  * Some fields are too dynamic as AWS justs adds more and more fields as the product features/attributes grow over time. Data structure will be changed to minimize the change, while preserving information so that things don't break everytime new fields are introduced.
* Loading into GCP services
  * BigQuery : main target.
  * Cloud Storage : to mirror files from AWS and intermediate files before loading into BigQuery

## observations

it is always good to start with some observations of what we are handling.

getting some basic questions answered first with exploring the main index file https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/index.json

### exploration

#### how many services?

```bash
ENDPOINT=https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/index.json
curl -s $ENDPOINT | jq -c .offers[] | wc -l
```

as of today, it returns 177.
that's worth an automation...

and the following gets you a list service names, that are used as the 'key' for retreive further info.

```bash
curl -s $ENDPOINT | jq -r .offers[].offerCode  | sort 
```

#### file structure

starting with the index file, will take a look at the portion for EC2. Using `AmazonEC2` which is the key for the service.

```bash
ENDPOINT=https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/index.json
curl -s $ENDPOINT | jq --arg OFFER AmazonEC2 '.offers[$OFFER]'
```

and you get this

```json
{
  "offerCode": "AmazonEC2",
  "versionIndexUrl": "/offers/v1.0/aws/AmazonEC2/index.json",
  "currentVersionUrl": "/offers/v1.0/aws/AmazonEC2/current/index.json",
  "currentRegionIndexUrl": "/offers/v1.0/aws/AmazonEC2/current/region_index.json",
  "savingsPlanVersionIndexUrl": "/savingsPlan/v1.0/aws/AWSComputeSavingsPlan/current/index.json",
  "currentSavingsPlanIndexUrl": "/savingsPlan/v1.0/aws/AWSComputeSavingsPlan/current/region_index.json"
}
```

basically the followings are the important ones.

* `versionIndexUrl` : is a **per offer** index file (in this case above, for EC2) where you can find the path to json files for each historical snapshot for a service.
* `currentVersionUrl` : but you can just reference this one if all you are interested in is the current catalog.

similar setup for SavingsPlan data for services where it applies.

#### how big are the files?

I do know from experience that the file for EC2 is gigantic. And that can be proved by the following.

```bash
$ curl -I ${ENDPOINT%/offers*}/offers/v1.0/aws/AmazonEC2/current/index.json
HTTP/1.1 200 OK
Content-Type: application/octet-stream
Content-Length: 2509834621
Connection: keep-alive
Last-Modified: Wed, 15 Sep 2021 16:52:14 GMT
x-amz-server-side-encryption: AES256
x-amz-version-id: 2XRDtdbzWlIP6g0iKDWc2D7BQDQ1l.LJ
Accept-Ranges: bytes
Server: AmazonS3
Date: Sun, 19 Sep 2021 02:37:15 GMT
ETag: "e124b823ff9bbeec0745fe2a1c8fff19"
X-Cache: Hit from cloudfront
Via: 1.1 0676a5fe6935c768360b164abce6620f.cloudfront.net (CloudFront)
X-Amz-Cf-Pop: SIN2-C1
X-Amz-Cf-Id: -H8ZI9yqccrBW6C9TUvD4H6fS-Wc7bXDm6cZSaABvl6mxp0GD-6IKg==
Age: 932
```

2.5GB for just a single snapshot of a single service's pricing data is quite insane.

I do see little value of Region index as it is normal to see some foot print across different regions, and I don't have limits in storage/compute capacity, so will default to using this even if large.

```bash
$ URL=$(curl -s ${ENDPOINT} | jq --arg PREFIX ${ENDPOINT%/offer*} -c -r '$PREFIX + .offers.AmazonEC2.currentRegionIndexUrl')
$ curl -I $(curl -s ${URL} | jq --arg PREFIX ${ENDPOINT%/offer*} -c -r '($PREFIX + .regions["ap-southeast-1"].currentVersionUrl)')
HTTP/1.1 200 OK
Content-Type: application/octet-stream
Content-Length: 149461529
Connection: keep-alive
Last-Modified: Wed, 15 Sep 2021 16:58:53 GMT
x-amz-server-side-encryption: AES256
x-amz-version-id: 7TZZV9R.LxrupuHB3aJj7HwKxpccO079
Accept-Ranges: bytes
Server: AmazonS3
Date: Sun, 19 Sep 2021 02:40:49 GMT
ETag: "dc0d8294fb37da14e6f17c8bcebf04a4"
X-Cache: Hit from cloudfront
Via: 1.1 54f86e61f2776ccac14162805d7331b2.cloudfront.net (CloudFront)
X-Amz-Cf-Pop: SIN2-C1
X-Amz-Cf-Id: xs-jk6RzjGw_88xGqGuOqa7fgJeIDqccg5K-ppMV4tfjF3Ye2c8xVA==
Age: 24
```

now it's down to 150MB. it might be worth taking this subset, if your interest can be scoped down, or you have limitation in compute/storage capacity.

#### versionIndexUrl

Is there no use of versionIndexUrl if we are only interested in the current?

Actually I do think there is. `current` is an alias to the latest version, easy to point to it as it is a static name, but you always want to know what exact version you are dealing with.

Some files (like the one for EC2 mentioned above) are so big, that you don't want to download and parse them just to get metadata, such as `version`. 

This is what the versionIndex file can look like

```bash
$ curl -s ${ENDPOINT%/offers*}/offers/v1.0/aws/AmazonEC2/index.json | head -n 15
{
  "formatVersion" : "v1.0",
  "disclaimer" : "This pricing list is for informational purposes only. All prices are subject to the additional terms included in the pricing pages on http://aws.amazon.com. All Free Tier prices are also subject to the terms included at https://aws.amazon.com/free/",
  "publicationDate" : "2021-09-15T16:12:09Z",
  "offerCode" : "AmazonEC2",
  "currentVersion" : "20210915161209",
  "versions" : {
    "20210616194700" : {
      "versionEffectiveBeginDate" : "2021-06-01T00:00:01Z",
      "versionEffectiveEndDate" : "2021-06-01T00:00:00Z",
      "offerVersionUrl" : "/offers/v1.0/aws/AmazonEC2/20210616194700/index.json"
    },
    "20180607191619" : {
      "versionEffectiveBeginDate" : "2018-05-01T00:00:00Z",
      "versionEffectiveEndDate" : "2018-06-01T00:00:00Z",
```

so you can get the version easily like this.

```bash
VERSION=$(curl -s ${ENDPOINT%/offers*}/offers/v1.0/aws/AmazonEC2/index.json | jq -r '.currentVersion')
echo $VERSION
```

#### json data structure

the file pointed by `versionUrl` is the main file to process.

The documentation [Reading an offer file](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/reading-an-offer.html) from AWS gets you and idea of the data structure of the file available. However, **it is not accurate** and does not match what I see. I wonder why that is. Maybe I am reading a older version of the data structure??

Anyway, let me take a real example from one of the smallest files for a service "A4B"

```json
{
  "formatVersion" : "v1.0",
  "disclaimer" : "This pricing list is for informational purposes only. All prices are subject to the additional terms included in the pricing pages on http://aws.amazon.com. All Free Tier prices are also subject to the terms included at https://aws.amazon.com/free/",
  "offerCode" : "A4B",
  "version" : "20200925212808",
  "publicationDate" : "2020-09-25T21:28:08Z",
  "products" : {
    "36GVC4SCXMHBN3ZH" : {
      "sku" : "36GVC4SCXMHBN3ZH",
      "productFamily" : "Enterprise Applications",
      "attributes" : {
        "servicecode" : "A4B",
        "location" : "US East (N. Virginia)",
        "locationType" : "AWS Region",
        "usagetype" : "USE1-EnrolledUser",
        "operation" : "",
        "deploymentModel" : "User",
        "deploymentModelDescription" : "Number of users who have enrolled their personal account to their organization and are managed by Alexa for Business",
        "servicename" : "Alexa for Business"
      }
    },
    "Q2FSX8AJGNAGR967" : {
      "sku" : "Q2FSX8AJGNAGR967",
      "productFamily" : "Enterprise Applications",
      "attributes" : {
        "servicecode" : "A4B",
        "location" : "US East (N. Virginia)",
        "locationType" : "AWS Region",
        "usagetype" : "USE1-SharedDevice",
        "operation" : "",
        "deploymentModel" : "Device",
        "deploymentModelDescription" : "Number of shared devices deployed and assigned location profile via console",
        "servicename" : "Alexa for Business"
      }
    }
  },
  "terms" : {
    "OnDemand" : {
      "36GVC4SCXMHBN3ZH" : {
        "36GVC4SCXMHBN3ZH.JRTCKXETXF" : {
          "offerTermCode" : "JRTCKXETXF",
          "sku" : "36GVC4SCXMHBN3ZH",
          "effectiveDate" : "2020-09-01T00:00:00Z",
          "priceDimensions" : {
            "36GVC4SCXMHBN3ZH.JRTCKXETXF.6YS6EN2CT7" : {
              "rateCode" : "36GVC4SCXMHBN3ZH.JRTCKXETXF.6YS6EN2CT7",
              "description" : "$3 per month for each user you have invited to join your Alexa for Business organization, prorated.",
              "beginRange" : "0",
              "endRange" : "Inf",
              "unit" : "Users",
              "pricePerUnit" : {
                "USD" : "3.0000000000"
              },
              "appliesTo" : [ ]
            }
          },
          "termAttributes" : { }
        }
      },
      "Q2FSX8AJGNAGR967" : {
        "Q2FSX8AJGNAGR967.JRTCKXETXF" : {
          "offerTermCode" : "JRTCKXETXF",
          "sku" : "Q2FSX8AJGNAGR967",
          "effectiveDate" : "2020-09-01T00:00:00Z",
          "priceDimensions" : {
            "Q2FSX8AJGNAGR967.JRTCKXETXF.6YS6EN2CT7" : {
              "rateCode" : "Q2FSX8AJGNAGR967.JRTCKXETXF.6YS6EN2CT7",
              "description" : "$7 per month for each shared device assigned to a \"room\", prorated.",
              "beginRange" : "0",
              "endRange" : "Inf",
              "unit" : "Devices",
              "pricePerUnit" : {
                "USD" : "7.0000000000"
              },
              "appliesTo" : [ ]
            }
          },
          "termAttributes" : { }
        }
      }
    }
  }
}
```

a few things to note

* some of the root level attributes like `offerCode` is retained in child structures (somehow with a different name like `servicecode` or `offerTermCode` ... why?? ), but some like `version` is not. so need to be careful what to retail/throwaway.
* there are two big parts to it. "Products", and "Terms". In are bigger service, these each can be huge. (for example, EC2 can have 519446 products and 1735333 terms, whereas, this A4B has only two each)  for usability, i will probably enrich Terms with Product info and have a denormalized form rather than two tables.
* heavily indexed. I imagine this is so that you can have a direct path to the part you need. perfect if you want to build something like a pricing estimation app where you know the key and want to do a K-V fetch, but useless if you don't know the keys. indexes are stored as attributes also so will collapse the structure and take the index layers out.
* product "attributes"
  * this can wildy change among services and even for the same service, changes over time. to have a more stable structure, will convert `{"foo":"bar"}` to `{"key":"foo", "value":"bar"}` structure.
  * some of the product attributes are commonly used across services and also useful in filtering skus. So will move these up to be at the product sku level direct attribute rather than be nested with others.

these are some of the observations and thoughts before implementing.

#### what if I took the whole historical catalog?

For the use case I had in mind, I do not need it, but if you want the ability to answer something like "how has this sku's pricing changed over time?", it make sense to get the whole. I did mirror everthing to Cloud Storage. It was just easy to do, and in the cloud, storage is not something to worry about.

This is how the overall accumulated downloaded raw files look like for my bucket as of today. (this does not include any regional files, so can be more depending on what you fetch)

```bash
$ gsutil du -s gs://$BUCKETNAME
280494881359
```

280GB. big? small? this is a relative thing. but I would say plenty of data to play around with.

## implementation technology

This does not require anything fancy.
Capabilities required are :

* downloading json files
* processing json files
* interacting with GCP services
* a little bit of automation

So will start with old school tools such as the followings, and see what might eventually be worth moving to proper serverless code.

* `curl`/`wget` : I am a person that cannot choose one over the other. sometimes, wget still gives nice flexibility or flags that curl does not and vice-versa.
* `jq` : my goto tool for scripting based json file manipulation
* Cloud SDK (`bq`, `gsutil`, `gcloud`)  : to do such things as "upload file to Cloud Storage", "load files into BigQuery", etc.
* `bash` : quick scripting to automate certain sequenced execution of above.
* `xargs` : to make execution much faster than for-loops
* `xxd`,`base64` : to decode/calculate ETag.

I know I will be iterating my scripts over time, and I will need to exoplore files and make decision on what to do with it. For better user/developer experience, I will probably still need some amount locally. But that will be considered temp files and my main data storage will be on Google Cloud Storage, which will be a mirror of what is available from AWS.

Environments :

* AWS : provided as publicly accessible files. I don't use AWS as my prime environment so just as a source.
* GCP - Cloud Storage : my own copy of all files fetched from above.
* Local : for my convenience. technically, if running everything on a vm on the cloud or Cloud Shell, not needed. But I want to use editors of my choice so will still use this.


## how to use

### Config

Change variables in `main.sh` to match your preference.

### Directory/Folders

Directories will be automatically created under the current working directory to store certain types of information. These can be changed to match your preference but not required to.

* `DIR_CACHE` : downloaded files will be treated as cache and store under this directory. structure will be direct reflection of the URL.
* `DIR_HEADERS` : HTTP Headers are also cached but in a separate directory. This is to efficiently fetch ETag or content size for verification, etc.
* `DIR_PROCESSED` : output from local data processing is stored here and then pushed to the cloud.
* `DIR_SQL` : SQL for joining or merging will be stored here so that it is easier to debug, should any failure happens.
* `DIR_ARTIFACTS` : some of the outcomes that might be worth version controlling or useful to have without the necessity of large downloads are stored here.


#### GCP Common

The variables below will need to meet your GCP env.

* `GCP_PROJECTNAME` : will automatically use what is set for your Cloud SDK, the output of `gcloud config list  --format="value(core.project)"`
* `REGION` (default : `asia-southeast1` (Singapore)) : the GCP region to be used. resources below will be created in this region.

#### Cloud Storage

* `BUCKET` : staging bucket.
* `BUCKET_WORK` : a bucket to be used to upload files to be loaded to BigQuery. can be the same as above.

#### BigQuery

* `BQ_PROJECT` (default : `<what is set to your Cloud SDK>` ): will default to the project set to Cloud SDK. sometimes you might want to have data loaded into BigQuery in another project, in which case you can set it here.
* `BQ_DATASET` (default : `aws_pricing` ): the main dataset where the final outcome will be stored.
* `BQ_DATASET_STAGING` (default : `aws_pricing_staging` ): data will be first loaded into the staging dataset, and then merged into the main dataset. thus, a separate dataset is needed. 
* `BQ_TABLE_PREFIX` (default : `aws_offers` ): a common prefix that will be used for table names.


## Usage

UNDER CONSTRUCTION

```bash
$ ./main.sh usage
usage :
./main.sh cacheRefreshMasterIndex
./main.sh clearCache
./main.sh clearHeaders
./main.sh pullAwsVersionIndexes
./main.sh pullAwsVersionIndexesFull
./main.sh pullAwsSavingsPlanVersionIndexes
./main.sh pullAwsOfferVersion <OFFER>
./main.sh pullAwsOfferVersion <OFFER> <VERSION>
./main.sh pullCurrentOffers
./main.sh pullLatestOffers
./main.sh preprocessOfferdata <OFFER> <VERSION>
./main.sh processAndLoadCurrentAll
./main.sh processAndLoadOfferVersion <OFFER>
./main.sh processAndLoadOfferVersion <OFFER> <VERSION>
./main.sh mergestaging2main
./main.sh createOfferTable
./main.sh recreateOfferTable
./main.sh cacheAndValidate <URL>
./main.sh createAwsOffersCurrentVersionUrlList
./main.sh createAwsOffersLatestVersionUrlList
./main.sh createAwsFullVersionIndexDownloadTsv
```

more details to be documented sometime....