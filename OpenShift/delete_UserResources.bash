#!/bin/bash

################################################################################################################
# Script that will delete all resources for the user $UserName (PV, PVC, POD, Namespace)
# Author: Fabrice MOYEN (IBM)


################################################################################################################
# VARIABLES

UserName=""
UserNamespace=""
UserDir=""
UserOption=0
DirOption=0
ForceOption=0

################################################################################################################
# FUNCTIONS

function usage
{
  echo
  echo "`basename $0` Usage:"
  echo "-------------------------"
  echo
  echo "Bash script used when you want to delete the resources of the provided OpensShift user"
  echo
  echo "Needed info to provide:"
  echo "-----------------------"
  echo "  + No parameters given => `basename $0` asks questions"
  echo "  + Missing parameters  => `basename $0` asks questions about the missing parameters"
  echo
  echo "  + -u <User Name> : the Openshift user name whose resources you want to be deleted"
  echo
  echo "Optional parameters:"
  echo "--------------------"
  echo "  + -d <directory> : Delete the provided directory (where the YAML files and scripts for this user are located)"
  echo "  + -f             : DANGEROUS: do not ask for any confirmation before deleting"
  echo
  echo "  + -h : shows this usage info"
  echo
  echo "Example:"
  echo "--------"
  echo "`basename $0`"
  echo "`basename $0` -u Fabrice"
  echo "`basename $0` -u Fabrice -d /tmp/Fabrice"
  echo "`basename $0` -u Fabrice -f"
  echo
  exit 0
}


################################################################################################################
# CHECKING IF PARAMETERS ARE GIVEN OR WE NEED TO ASK QUESTIONS
#

while getopts ":u:d:fh" option; do
  case $option in
    u)
      UserName=$OPTARG
      UserOption=1
    ;;
    d)
      UserDir=$OPTARG
      DirOption=1
    ;;
    f)
      ForceOption=1
    ;;
    h)
      usage
    ;;

    \?) echo "Unknown option: -$OPTARG" >&2; exit 1;;
    :) echo "Missing option argument for -$OPTARG" >&2; exit 1;;
    *) echo "Unimplemented option: -$OPTARG" >&2; exit 1;;
  esac
done


################################################################################################################
# ASKING FOR THE USER NAME

if [ $UserOption -eq 0 ]; then
  while [[ "$UserName" == "" ]]; do
    echo
    echo "What is the OpenShift user name ? (the user who owns the resources you want to delete) ? :"
    echo "------------------------------------------------------------------------------------------"
    read UserName
  done

else
  echo
  echo "========================================================================================================================================="
  echo "USER NAME: $UserName"
  echo "========================================================================================================================================="
fi

UserNamespace="$UserName-project"


################################################################################################################
# DELETING THE USER RESOURCES

if [ $ForceOption -eq 0 ]; then
  echo
  echo "WARNING: Are you sure you want to proceed deleting $UserName resources ??"
  if [ $DirOption -eq 1 ]; then
    echo "         (and also deleting the following directory: $UserDir)"
  fi
  echo "(Enter or CTRL-C NOW !)"
  read confirmation
fi

echo
echo "========================================================================================================================================="
echo "DELETING RESOURCES FOR USER $UserName..."
echo
echo "Warning: PVC deletion may take a minute as it needs to wait for Pod complete deletion"
echo "         Namespace deletion is also not instantaneous"
echo "-----------------------------------------------------------------------------------------------------------------------------------------"

# Deleting the Deployment (with the ReplicatSet and the Pod coming with it)
echo
echo "oc -n $UserNamespace delete deployment.apps/oc-$UserName-ad9h3"
oc -n $UserNamespace delete deployment.apps/oc-$UserName-ad9h3

# Deleting PVC & PV
echo
echo "oc -n $UserNamespace delete persistentvolumeclaim/images-$UserName-pvc"
oc -n $UserNamespace delete persistentvolumeclaim/images-$UserName-pvc

echo
echo "oc delete persistentvolume/images-$UserName"
oc delete persistentvolume/images-$UserName

# Deleting the NameSpace
echo
echo "oc delete namespace $UserNamespace"
oc delete namespace $UserNamespace

# Deleting the user Yaml directory
echo
echo "Deleting $UserDir directory"
echo "rm -rf $UserDir"
rm -rf $UserDir

echo "========================================================================================================================================="
echo
