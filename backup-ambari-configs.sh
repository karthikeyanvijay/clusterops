#!/bin/bash
#
# Script to backup Ambari Configuration. The script requires jq to be installed on the system.
# This script can be used in three modes
#    1)  By supplying all the parameters as part of the execution
#    2)  Supplying a config file containing all the required parameters.
#    3)  If both the config file & the other parameters are supplied. The parameters which take effect depends on the position of the parameter.
#        Any parameter supplied before the config file is overwritten by the values from the config file.
#        Any paramters supplied via command line after the config file takes precedent over the config file.
#        
# ./backup-ambari-configs.sh -e http://<ambari-host>:8080 -n CLUSTERNAME -u admin -p admin -d /tmp/backups
#
#  Author:  Vijay Anand Karthikeyan
#

OPTS=`getopt -o e:n:u:p:d:c: --long ambariurl:,clustername:,username:,password:,backupdir:configfile:,help:: -n 'parse-options' -- "$@"`

function log {
    echo "`date '+%Y-%m-%d %H:%M:%S'` ${*}"
}

scriptUsage()
{
  log "INFO ---------------------------------------------------------------------------------------"
  log "INFO Please supply the required parameters for the script."
  log "INFO "
  log "INFO Usage 1: "
  log "INFO          $(basename -- "$0") -e http://<ambari-host>>:8080 -u admin -p admin -d /tmp/backups"
  log "INFO          Mandatory Parameters:"
  log "INFO                       -e | --ambariurl    Ambari URL with port"
  log "INFO                       -n | --clustername  Cluster Name" 
  log "INFO                       -u | --username     User Name"
  log "INFO                       -p | --password     Password"
  log "INFO                       -d | --backupdir    Directory used for backup"
  log "INFO "
  log "INFO "
  log "INFO Usage 2: "
  log "INFO          $(basename -- "$0") -c .prod.secret "
  log "INFO          Mandatory Parameters:"
  log "INFO                       -c | --configfile   "
  log "INFO                       File which supplies the AMBARIURL,CLUSTERNAME,AMBARIUSERNAME,AMBARIPASSWORD & BACKUPDIR environment variables"
  log "INFO "
  log "INFO "
  log "INFO Usage 3: "
  log "INFO          $(basename -- "$0") -c .prod.secret -d /tmp/backups"
  log "INFO          Mandatory Parameters:"
  log "INFO                       A combination of Usage 1 & 2 "
  log "INFO                       All required parameters need to be supplied either through config file or the command line parameter "
  log "INFO                       The parameters which take effect depends on the position of the parameter."
  log "INFO                       Any parameter supplied before the config file is overwritten by the values from the config file."
  log "INFO                       Any paramters supplied via command line after the config file takes precedent over the config file."
  log "INFO "
  log "INFO ---------------------------------------------------------------------------------------"
}

if [ $? != 0 ] ; then log "ERROR Failed parsing options." >&2 ; exit 1 ; fi

while true; do
  case "$1" in
    -e | --ambariurl ) 
            case "$2" in
                *) AMBARIURL=$2 ; shift 2 ;;
            esac ;;
    -n | --clustername )
            case "$2" in
                *) CLUSTERNAME=$2 ; shift 2 ;;
            esac ;;
    -u | --username )
            case "$2" in
                *) AMBARIUSERNAME=$2 ; shift 2 ;;
            esac ;;
    -p | --password )
            case "$2" in
                *) AMBARIPASSWORD=$2 ; shift 2 ;;
            esac ;;
    -d | --backupdir )
            case "$2" in
                *) BACKUPDIR=$2 ; shift 2 ;;
            esac ;;
    -c | --configfile )
            case "$2" in
                *) CONFIGFILE=$2 ; 
                    if [ "x" != "x$CONFIGFILE" ] ; then
                      log "INFO Config file $CONFIGFILE supplied"
                      source $CONFIGFILE
                      if [ $? -eq 0 ]; then
                        log "INFO Source parameters from $CONFIGFILE file complete."
                      else
                        log "INFO Unable to get parameters from $CONFIGFILE"
                        # Not increasing failcount & logging INFO, not error
                      fi
                    fi
                    shift 2 ;;
            esac ;;
    -- ) shift; break ;;
    * ) break ;;
  esac
done

log "INFO ---------------------------------------------------------------------------------------"
log "INFO Parameters supplied for this run - "
log "INFO     Script name:        $(basename -- ""$0"")"
log "INFO     Ambari URL:         $AMBARIURL"
log "INFO     Cluster Name:       $CLUSTERNAME"
log "INFO     Username:           $AMBARIUSERNAME"
log "INFO     Backup Directory:   $BACKUPDIR"
log "INFO ---------------------------------------------------------------------------------------"

if [ "x" == "x$AMBARIUSERNAME" ] || [ "x" == "x$AMBARIURL" ] || [ "x" == "x$AMBARIPASSWORD" ] || [ "x" == "x$BACKUPDIR" ] || [ "x" == "x$CLUSTERNAME" ] ; then
  scriptUsage
  exit 1
fi

create_Directory()
{
  log "INFO ---------------------------------------------------------------------------------------"
  if [[ ! -e $BACKUPDIR ]]; then
      createdir=`mkdir -p $BACKUPDIR`
      if [ $? -eq 0 ]; then
          log "INFO Creation of directory $BACKUPDIR complete."
          return
      else
          log "ERROR Unable to create directory $BACKUPDIR" >&2
          failCount=$((failCount+1))
          exit 3
      fi
  elif [[ ! -d $BACKUPDIR ]]; then
      log "ERROR $BACKUPDIR already exists but is not a directory. Exiting program." >&2
      failCount=$((failCount+1))
      exit 4
  elif [[  -d $BACKUPDIR ]]; then
      log "INFO $BACKUPDIR Directory already exists."
  fi
  log "INFO ---------------------------------------------------------------------------------------"
}

get_AmbariConfigs()
{
  log "INFO ---------------------------------------------------------------------------------------"
  configs=`curl -sfk -H "X-Requested-By: ambari" -X GET -u $AMBARIUSERNAME:$AMBARIPASSWORD $AMBARIURL/api/v1/clusters/$CLUSTERNAME?fields=Clusters/desired_configs | jq -r ".Clusters.desired_configs" | jq -r 'keys[] as $k | "\($k),\(.[$k] | .tag),\(.[$k] | .version)"'`
  if [ $? -eq 0 ]; then
      log "INFO Got list of configurations for cluster: $CLUSTERNAME"
  else
      log "ERROR Unable to get the list of configurations from Ambari" >&2
      failCount=$((failCount+1))
      log
  fi
  
  log "INFO Backing up to directory: $BACKUPDIR"
  echo "$configs" | while IFS= read -r line ; 
    do
    	config=`echo $line | tr -d [:blank:] | cut -d, -f1`
     	tag=`echo $line | tr -d [:blank:] | cut -d, -f2`
     	getConfig=`curl -sk -H "X-Requested-By: ambari" -X GET -u $AMBARIUSERNAME:$AMBARIPASSWORD "$AMBARIURL/api/v1/clusters/$CLUSTERNAME/configurations?type=${config}&tag=${tag}" -o "$BACKUPDIR/${config}"`
      if [ $? -eq 0 ]; then
          log "INFO  Get configs complete for Config=$config Tag=$tag"
      else
          log "ERROR  Get configs failed for Config=$config Tag=$tag" >&2
          failCount=$((failCount+1))
          continue
      fi
    done
  log "INFO ---------------------------------------------------------------------------------------"
}

get_AmbariBlueprint()
{
  log "INFO ---------------------------------------------------------------------------------------"
  log "INFO Getting blueprint..."
  getBlueprint=`curl -skf -u $AMBARIUSERNAME:$AMBARIPASSWORD "$AMBARIURL/api/v1/clusters/${CLUSTERNAME}?format=blueprint" -o "$BACKUPDIR/${CLUSTERNAME}_blueprint.json"`
  if [ $? -eq 0 ]; then
    log "INFO  Get blueprint for cluster $CLUSTERNAME complete."
  else
    log "ERROR  Get blueprint for cluster $CLUSTERNAME failed." >&2
    failCount=$((failCount+1))
    return
  fi
  log "INFO ---------------------------------------------------------------------------------------"
}

list_allFiles()
{
  log "INFO ---------------------------------------------------------------------------------------"
  log "INFO Listing all files created in the directory: $1"
  log "INFO ---------------------------------------------------------------------------------------"
  allfile=`ls -ltr $1/*`
  if [ $? -eq 0 ]; then
      log "INFO "
  else
      log "ERROR Unable to get list of files for $BACKUPDIR" >&2
      failCount=$((failCount+1))
      return
  fi
  log "INFO "
  log "INFO $allfile"
  log "INFO ---------------------------------------------------------------------------------------"
}

#----------------------------------------- Main section -----------------------------------------#
failCount=0
create_Directory
get_AmbariConfigs
get_AmbariBlueprint
list_allFiles $BACKUPDIR
log "INFO ---------------------------------------------------------------------------------------"
if [ "$failCount" -gt 0 ]; then
  log "ERROR Script $(basename -- "$0") failed. Number of failures: $failCount" >&2
  log "INFO ---------------------------------------------------------------------------------------"
  exit 5
else
  log "INFO All steps completed successfully."
fi
log "INFO ---------------------------------------------------------------------------------------"

