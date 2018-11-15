#!/bin/bash
#
# Script to backup Ranger Policies
# This script can be used in three modes
#    1)  By supplying all the parameters as part of the execution
#    2)  Supplying a config file containing all the required parameters.
#    3)  If both the config file & the other parameters are supplied. The parameters which take effect depends on the position of the parameter.
#        Any parameter supplied before the config file is overwritten by the values from the config file.
#        Any paramters supplied via command line after the config file takes precedent over the config file.
#
# Usage:
#        Use ./backup-ranger-policies.sh --help to get the usage
#
#  Author:  Vijay Anand Karthikeyan
#

OPTS=`getopt -o e:u:p:d:c: --long rangerurl:,username:,password:,backupdir:configfile:,help:: -n 'parse-options' -- "$@"`

function log {
    echo "`date '+%Y-%m-%d %H:%M:%S'` ${*}"
}

scriptUsage()
{
  log "INFO ---------------------------------------------------------------------------------------"
  log "INFO Please supply the required parameters for the script."
  log "INFO Usage 1: "
  log "INFO          $(basename -- ""$0"") -e http://<ranger-host>>:<<port>> -u admin -p admin -d /tmp/backups"
  log "INFO          Mandatory Parameters:"
  log "INFO                       -e | --rangerurl   Ranger URL with port"
  log "INFO                       -u | --username    User Name"
  log "INFO                       -p | --password    Password"
  log "INFO                       -d | --backupdir   Directory used for backup"
  log "INFO "
  log "INFO "
  log "INFO Usage 2: "
  log "INFO          $(basename -- "$0") -c .prod.secret "
  log "INFO          Mandatory Parameters:"
  log "INFO                       -c | --configfile   "
  log "INFO                       File which supplies the RANGERURL,RANGERUSERNAME,RANGERPASSWORD & BACKUPDIR environment variables"
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
  log "INFO ---------------------------------------------------------------------------------------"
}

if [ $? != 0 ] ; then log "ERROR Failed parsing options." >&2 ; exit 1 ; fi

while true; do
  case "$1" in
    -e | --rangerurl ) 
            case "$2" in
                *) RANGERURL=$2 ; shift 2 ;;
            esac ;;
    -u | --username )
            case "$2" in
                *) RANGERUSERNAME=$2 ; shift 2 ;;
            esac ;;
    -p | --password )
            case "$2" in
                *) RANGERPASSWORD=$2 ; shift 2 ;;
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
    --help ) scriptUsage; exit 0; break ;;
    -- ) shift; break ;;
    * ) break ;;
  esac
done

log "INFO ---------------------------------------------------------------------------------------"
log "INFO Parameters supplied for this run - "
log "INFO     Script name:        $(basename -- ""$0"")"
log "INFO     Ranger URL:         $RANGERURL"
log "INFO     Username:           $USERNAME"
log "INFO     Backup Directory:   $BACKUPDIR"
log "INFO ---------------------------------------------------------------------------------------"

if [ "x" == "x$RANGERUSERNAME" ] || [ "x" == "x$RANGERURL" ] || [ "x" == "x$RANGERPASSWORD" ] || [ "x" == "x$BACKUPDIR" ] ; then
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

get_RangerPolicies()
{
  log "INFO ---------------------------------------------------------------------------------------"
  log "INFO Getting Ranger Policies..."
  getPolicies=`curl -sfk -X GET --header "text/json" -H "Content-type:application/json" -u $RANGERUSERNAME:$RANGERPASSWORD $RANGERURL/service/plugins/policies/exportJson -o "$BACKUPDIR/ranger_policies.json"`
  if [ $? -eq 0 ]; then
    log "INFO  Get Ranger Policies complete for cluster $CLUSTERNAME complete."
  else
    log "ERROR  Get Ranger Policies for cluster $CLUSTERNAME failed." >&2
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
get_RangerPolicies
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
