#!/bin/bash

set +x
shopt -s expand_aliases
alias echoi='echo `date +%Y-%m-%d\ %H:%M.%S` -INFO-'
alias echoe='echo `date +%Y-%m-%d\ %H:%M.%S` -ERROR-'

echoi STARTing
SCRIPT_LOC=`pwd`

#############################################################################################################
### Parameters, settings and blablabla
. /home/neo4j/.bash_profile
. /opt/reuters/apps/env/neo4j.env

if [ $# -ne 3 ]
then
  echoe "Please pass parameters: "
  echoe "                        CLOUD_ENVIRONMENT"
  echoe "                        CLOUD_DEV_PHASE"
  echoe "                        EC2_REGION"
  exit 1
fi

CLOUD_ENVIRONMENT=$1
CLOUD_DEV_PHASE=$2
EC2_REGION=$3

# This script configuration goes in <thisScriptName>.conf
. ./`basename $0`.conf




#############################################################################################################
### Copying from S3
LAST_S3DIR=`aws s3 ls s3://$BUCKET_NAME/$BUCKET_ROUTE/ | grep -v ":" | awk '{print $2}'| sort -r | head -n 1`
if [[ ${#LAST_S3DIR} -eq 0  ]]; then
  echoe Unable to find LAST_S3DIR; returned LAST_S3DIR=$LAST_S3DIR
  exit 10
fi
LAST_S3DIR=${LAST_S3DIR%?}

TAR_FILE=`aws s3 ls s3://$BUCKET_NAME/$BUCKET_ROUTE/$LAST_S3DIR/ | awk '{print $4}'`
if [[ $TAR_FILE == ''  ]]; then
  echoe Unable to find TAR_FILE; returned TAR_FILE=$TAR_FILE
  exit 10
fi

echoi Cleaning up $TAR_DEST_DIR/
rm -f $TAR_DEST_DIR/*

COPY_CMD="aws s3 cp s3://$BUCKET_NAME/$BUCKET_ROUTE/$LAST_S3DIR/$TAR_FILE  $TAR_DEST_DIR/ > /dev/null"
echoi Copying tarball file to import directory
echoi $COPY_CMD
$COPY_CMD
if [[ ! -e $TAR_DEST_DIR/$TAR_FILE ]]; then
  echoe Unable to copy file $TAR_FILE
  exit 10
fi



#############################################################################################################
### Uncompress
cd $TAR_DEST_DIR/
echoi Uncompressing $TAR_FILE in $TAR_DEST_DIR/
tar -xvzf $TAR_DEST_DIR/$TAR_FILE --directory $TAR_DEST_DIR/ > /dev/null

nodeFilesCnt=`ls *_nodes.csv | wc -l`
relFilesCnt=`ls *rels.csv | wc -l`


#############################################################################################################
### Import
IMPORT_PARAMS=" --id-type string --array-delimiter \"¬\" --skip-bad-relationships=false --multiline-fields=true "
executeMe="$NEO4J_HOME/bin/neo4j-import --into $DB_DIR/$TEMP_DB_NAME $IMPORT_PARAMS "

for myFile in *_nodes.csv
do
  executeMe="$executeMe --nodes $TAR_DEST_DIR/$myFile"
done

for myFile in *_rels.csv
do
  executeMe="$executeMe --relationships $TAR_DEST_DIR/$myFile"
done

rm -f $IMP_LOG_FILE
rm -rf $DB_DIR/$TEMP_DB_NAME 2> /dev/null
mkdir -p $DB_DIR/$TEMP_DB_NAME 2> /dev/null
chmod 777 $DB_DIR/$TEMP_DB_NAME 2> /dev/null

echoi Executing import
echoi Node files count: $nodeFilesCnt, Relationship files count: $relFilesCnt
#eval $executeMe > $IMP_LOG_FILE
eval $executeMe > $IMP_LOG_FILE

if [ $? -ne 0 ]; then
   echoe Error in importing, please check debug.log file and/or bad.log
   exit 20
fi
if [ -s $DB_DIR/$TEMP_DB_NAME/bad.log ]; then
   echoe Error in importing, bad.log file exists; exiting
   exit 20
fi

export timeTaken=`tail -5 $IMP_LOG_FILE | grep "IMPORT DONE" | cut -d "." -f 1 | cut -d " " -f 4,5,6,7,8,9,10`
export nodesLoaded=`tail -5 $IMP_LOG_FILE | grep "nodes" | cut -d " " -f 3`
export relsLoaded=`tail -5 $IMP_LOG_FILE | grep "relationships" |  cut -d " " -f 3`
export propsLoaded=`tail -5 $IMP_LOG_FILE | grep "properties" |  cut -d " " -f 3`
echoi "Import done - loaded $nodesLoaded nodes, $relsLoaded relationships, $propsLoaded properties"

chown -R neo4j:neo4j $DB_DIR/
chmod -R 766 $DB_DIR/
rm -rf $DB_DIR/$REAL_DB_NAME
mv $DB_DIR/$TEMP_DB_NAME $DB_DIR/$REAL_DB_NAME


#############################################################################################################
### Restarting server
echoi Restarting neo4j server...
(/etc/init.d/neo4j restart || /etc/init.d/neo4j-server restart || service neo4j restart) > /dev/null 2>&1
if [ $? -ne 0 ]; then
   echoe Error in starting neo4j instance; exiting
   exit 30
fi

#echoi Waiting for neo4j to be available...
echoi ...
sleep 5

isStarted=0

while [[ isStarted -lt 1 ]]
do
  echoi ...
  sleep 5
  isStarted=`tail -4 /var/log/neo4j/neo4j.log | grep "INFO  Remote interface available at" | wc -l`
  let timer=timer+1
  if [[ timer -gt 20 ]]; then
    echoe Neo4j seems not starting, please check /var/log/neo4j/neo4j.log; exiting
    exit 30
  fi
done

echoi Neo4j seems to be started

echoi Executing post-import script $postImportCypher
export myDate=`date`
$NEO4J_HOME/bin/neo4j-shell -c "create (x:_dbInfo   { dbCreateDate: '$myDate',timeTaken: '$timeTaken', nodesLoaded: $nodesLoaded, relationshipsLoaded: $relsLoaded, propertiesLoaded: $propsLoaded, nodesFilesCount: $nodeFilesCnt, relationshipsFileCount: $relFilesCnt }  );" >/dev/null 2>&1

echoi ENDing
