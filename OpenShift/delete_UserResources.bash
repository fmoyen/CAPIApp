#!/bin/bash

################################################################################################################
# Script that will delete an OpenShift user and all his associated resources (PV, PVC, POD, Namespace)
# Author: Fabrice MOYEN (IBM)


################################################################################################################
# VARIABLES

#---------------------------------------------------------------------------------------------------------------
# Variables you may want to change

# The name used for the htpasswd Identity Provider we've created
IDProviderName="opfh-htpasswd"

RBACUserRole="view"

#---------------------------------------------------------------------------------------------------------------
# Variables you don't need to change

SecretName="${IDProviderName}-secret"

UserName=""
CardName="nul"
UserNamespace=""
UserDir=""
UserOption=0
CardOption=0
DirOption=0
ForceOption=0

TempDir=/tmp
HtpasswdFile=$TempDir/users.htpasswd
TempFile=$TempDir/delete_UserResources.tmp

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
  echo "  + -c <Card Name> : the type of card that the user has requested (the card type is used in the user's resource name. That's why we need to know it)"
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
  echo "`basename $0` -u Fabrice -c ad9h3 -d /tmp/Fabrice -f"
  echo
  exit 0
}


################################################################################################################
# CHECKING IF PARAMETERS ARE GIVEN OR WE NEED TO ASK QUESTIONS
#

while getopts ":u:c:d:fh" option; do
  case $option in
    u)
      UserName=$OPTARG
      UserOption=1
    ;;
    c)
      CardName=$OPTARG
      CardOption=1
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

clear

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
# ASKING FOR THE CARD

TrapCmd="rm -f $TempFile"
touch $TempFile
trap "$TrapCmd" EXIT

NodeList=`oc get nodes | grep worker | awk '{print $1}'`

for Node in $NodeList; do
  echo $Node  >> $TempFile
  oc describe node $Node | sed -n '/Capacity:/,/Allocatable/p' | grep xilinx.com >> $TempFile
done

if [ $CardOption -eq 0 ]; then
  while ! grep -q $CardName $TempFile; do
    echo
    echo "Please choose between the following card type:"
    echo "----------------------------------------------"
    cat $TempFile | grep xilinx.com | awk -F"-" '{print $2}' | awk -F"_" '{print $1}' | sort | uniq
    echo -e "?: \c"
    read CardName
  done
fi


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
echo "Warning:"
echo "  Some deletion operations such as deleting PVC and namespace, may not be instantaneous"
echo "  (for example, PVC deletion needs to wait for Pod complete deletion)"
echo "-----------------------------------------------------------------------------------------------------------------------------------------"

# Removing the RBAC User Roles
echo
echo "-----------------------------------------------------------------------------------------------------------------------------------------"
echo "oc adm policy remove-role-from-user $RBACUserRole $UserName -n $UserNamespace"
oc adm policy remove-role-from-user $RBACUserRole $UserName -n $UserNamespace
echo
echo "oc adm policy remove-role-from-user pod-shell $UserName --role-namespace=$UserNamespace -n $UserNamespace"
oc adm policy remove-role-from-user pod-shell $UserName --role-namespace=$UserNamespace -n $UserNamespace

# Deleting the Deployment (with the ReplicatSet and the Pod coming with it)
echo
echo "-----------------------------------------------------------------------------------------------------------------------------------------"
echo "oc -n $UserNamespace delete deployment.apps/oc-$UserName-$CardName"
oc -n $UserNamespace delete deployment.apps/oc-$UserName-$CardName

# Deleting PVC & PV
echo
echo "-----------------------------------------------------------------------------------------------------------------------------------------"
echo "oc -n $UserNamespace delete persistentvolumeclaim/images-$UserName-pvc"
oc -n $UserNamespace delete persistentvolumeclaim/images-$UserName-pvc

echo
echo "oc delete persistentvolume/images-$UserName"
oc delete persistentvolume/images-$UserName

# Deleting the NameSpace
echo
echo "-----------------------------------------------------------------------------------------------------------------------------------------"
echo "oc delete namespace $UserNamespace"
oc delete namespace $UserNamespace

# Deleting the user and identity
trap "rm -f $HtpasswdFile" EXIT

echo
echo "-----------------------------------------------------------------------------------------------------------------------------------------"
echo "oc get secret $SecretName -ojsonpath={.data.htpasswd} -n openshift-config | base64 --decode > $HtpasswdFile"
oc get secret $SecretName -ojsonpath={.data.htpasswd} -n openshift-config | base64 --decode > $HtpasswdFile  # Save the current Openshift secret config into an htpasswd file

echo
echo "htpasswd -D $HtpasswdFile $UserName"
htpasswd -D $HtpasswdFile $UserName  # Delete $user info from the htpasswd file

echo
echo "oc create secret generic $SecretName --from-file=htpasswd=$HtpasswdFile --dry-run=client -o yaml -n openshift-config | oc replace -f -"
oc create secret generic $SecretName --from-file=htpasswd=$HtpasswdFile --dry-run=client -o yaml -n openshift-config | oc replace -f -  # update the Openshift secret config

echo
echo "oc delete user $UserName"
oc delete user $UserName

echo
echo "oc delete identity $IDProviderName:$UserName"
oc delete identity $IDProviderName:$UserName

# Deleting the user Yaml directory
if [ $DirOption -eq 1 ]; then
  echo
  echo "-----------------------------------------------------------------------------------------------------------------------------------------"
  echo "Deleting $UserDir directory"
  echo "rm -rf $UserDir"
  rm -rf $UserDir
fi

echo "========================================================================================================================================="
echo
