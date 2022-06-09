#!/bin/bash

################################################################################################################
# Script that will delete all resources for the user $UserName (PV, PVC, POD, Namespace)
# Author: Fabrice MOYEN (IBM)


################################################################################################################
# VARIABLES

UserName=""
UserNamespace=""
UserOption=0
RunOption=0

################################################################################################################
# FUNCTIONS

function usage
{
  echo
  echo "`basename $0` Usage:"
  echo "-------------------------"
  echo
  echo "Bash script used when a standard user wants a POD with an OpenCAPI card"
  echo
  echo "  + No parameters given => `basename $0` asks questions"
  echo "  + Missing parameters  => `basename $0` asks questions about the missing parameters"
  echo
  echo "  + -u <User Name> : to give your user name"
  echo "  + -r             : Dangerous: do not ask for any confirmation before deleting"
  echo
  echo "  + -h : shows this usage info"
  echo
  echo "Example:"
  echo "--------"
  echo "`basename $0`"
  echo "`basename $0` -u Fabrice"
  echo "`basename $0` -u Fabrice -r"
  echo
  exit 0
}


################################################################################################################
# CHECKING IF PARAMETERS ARE GIVEN OR WE NEED TO ASK QUESTIONS
#

while getopts ":u:rh" option; do
  case $option in
    u)
      UserName=$OPTARG
      UserOption=1
    ;;
    r)
      RunOption=1
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
    echo "What is the user name ? (user owning the resources you want to delete special character) ? :"
    echo "--------------------------------------------------------------------------------------------"
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

if [ $RunOption -eq 0 ]; then
  echo
  echo "WARNING: ARE YOU SURE YOU WANT TO PROCEED DELETING $UserName RESOURCES ??"
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

echo "========================================================================================================================================="
echo
