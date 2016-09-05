#!/bin/bash

set +x

. /home/neo4j/.bash_profile
. /opt/reuters/apps/env/neo4j.env

shopt -s expand_aliases
alias echoi='echo `date +%Y-%m-%d\ %H:%M.%S` -INFO-'
alias echoe='echo `date +%Y-%m-%d\ %H:%M.%S` -ERROR-'

echoi STARTing

outFile=/tmp/`basename $0`.out

if [ $# -eq 1 ]
then
  cyptherFile=$1
else
  cyptherFile=`basename $0`.cy
fi

echoi Executing script file $cyptherFile
echoi Logging output in $outFile

$NEO4J_HOME/bin/neo4j-shell -file "$1" >$outFile 2>&1

if [ $? -ne 0 ]; then
  echoe "Error executing shell; exiting"
  exit 30
fi

if [[ `grep -i error $outFile` ]]; then
  echoe "Error found in out file; exiting"
  exit 30
fi

echoi ENDing
