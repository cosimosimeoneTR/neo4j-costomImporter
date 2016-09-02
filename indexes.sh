#!/bin/bash

set +x

shopt -s expand_aliases
alias echoi='echo `date +%Y-%m-%d\ %H:%M.%S` -INFO-'
alias echoe='echo `date +%Y-%m-%d\ %H:%M.%S` -ERROR-'

echoi STARTing

if [ $# -ne 1 ]
  then
    echoe "Please pass script file name"
    exit 1
fi
outFile=/tmp/`basename $0`.out


. /home/neo4j/.bash_profile
. /opt/reuters/apps/env/neo4j.env


echoi Executing script in $1
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
