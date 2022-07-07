#!/bin/bash

clear


################################################################################################################
# Bash script used when a standard user wants a POD with an OpenCAPI card
# Author: Fabrice MOYEN (IBM)

# We need to:
#  - ask for the user name
#  - ask for the type of card requested (like ad9h3)
#  - generate the namespace (project) with the user name
#  - give access to the namespace for the user (RBAC Role)
#  - generate the yaml definition files (project, name, etc)
#  - generate a script to delete all user/namespace resources when not needed anymore
#  - generate the PV/PVC pointing to the user binaries directory
#  - create the POD/container with access to the volume hosting the user partial binaries
#
# Parameters to adapt to the environment once:
#  - UserYAMLRootDir : where all the scripts needed to generate the user environment (and to delete it) will be stored


################################################################################################################
# VARIABLES

Verbose=0

RealPath=`realpath $0`
RealPath=`dirname $RealPath`

YamlDir="$RealPath/OPENCAPI-user-device_requested/current/OCAPI_requested"

YamlFile=`ls $YamlDir/OPENCAPI-*-deploy.yaml 2>/dev/null | head -1`
ImagesDevice_PvYamlFile=`ls $YamlDir/images-user-pv.yaml 2>/dev/null`
ImagesDevice_PvcYamlFile=`ls $YamlDir/images-user-pvc.yaml 2>/dev/null`

UserYAMLRootDir=/tmp
UserResourcesDeleteScript="deleteUserResources.bash"
UserNSCreationFile="createUserNamespace.bash"
DockerSecretCreationFile="createDockerSecret.bash"

RBACUserRole="edit"

UserName=""
UserPassword=""
UserNamespace=""
CardType=""
CardName="nul"
DockerUser=""
DockerPassword=""

UserOption=0
UserPasswordOption=0
CardOption=0
DockerUserOption=0
DockerPasswordOption=0

TempDir=/tmp
TempFile=$TempDir/user_CAPIapp.tmp
OauthInitialConfig=$TempDir/oauth_initial.json
OauthFinalConfig=$TempDir/oauth_final.json
HtpasswdFile=$TempDir/opfh_users.htpasswd


################################################################################################################
# FUNCTIONS
#

#===============================================================================================================
function usage
{
  echo
  echo "`basename $0` Usage:"
  echo "-------------------------"
  echo
  echo "Bash script used when a standard user wants a POD with an OpenCAPI card"
  echo
  echo "Needed info to provide:"
  echo "-----------------------"
  echo "  + No parameters given => `basename $0` asks questions"
  echo "  + Missing parameters  => `basename $0` asks questions to get the missing parameters"
  echo
  echo "  + -u <User Name>     : the OpenShift user name"
  echo "  + -p <User Password> : the OpenShift user password"
  echo "  + -c <Card Name>     : the type of card requested"
  echo
  echo "Optional parameters:"
  echo "--------------------"
  echo "  + -d <Docker User>     : Docker username to be used by the OpenShift default service account of the user namespace when downloading Docker images"
  echo "  + -s <Docker Password> : Docker password (s= secret) when downloading Docker images. `basename $0` will ask for it if needed"
  echo
  echo "Docker pull rates limits are based on individual IP address. For anonymous users, the rate limit is set to 100 pulls per 6 hours per IP address."
  echo "  ==> From a corporate network, the 100 pulls limit can be reached quickly"
  echo "For Docker authenticated users, the rate limit is set to 200 pulls per 6 hour period per user, which is much more confortable."
  echo
  echo "  + -v                   : verbose output"
  echo "  + -h                   : this usage info"
  echo
  echo "Example:"
  echo "--------"
  echo "`basename $0`"
  echo "`basename $0` -u Fabrice"
  echo "`basename $0` -u Fabrice -s XXXX -c ad9h3"
  echo "`basename $0` -u Fabrice -c ad9h3 -d fmoyen"
  echo "`basename $0` -u Fabrice -s XXXX -c ad9h3 -d fmoyen -s YYYY -v"
  echo
  exit 0
}


#===============================================================================================================
function Add_User_Definition
{
  local user=$1
  local password=$2
  
  TrapCmd="$TrapCmd; rm -f $OauthInitialConfig $OauthFinalConfig $HtpasswdFile"
  trap "$TrapCmd" EXIT

  #-------------------------------------------------------------------------------------------------------------
  # Create a new $HtpasswdFile file with $user/$password info AND Create an Openshift secret thanks to the $HtpasswdFile file
  #   OR
  # Save the users info from the already existing OpenShift secret into $HtpasswdFile file AND Add $user/$password info to the file AND update the OpenShift secret with the file

  if ! oc get secret opfh-htpass-secret -n openshift-config > /dev/null 2>&1; then 
    echo
    echo "Creating a new OpenShift secret (opfh-htpass-secret) with $user info"
    echo "--------------------------------------------------------------------------"
    [ $Verbose -eq 1 ] && echo "htpasswd -c -Bb $HtpasswdFile $user XXXX"
    htpasswd -c -Bb $HtpasswdFile $user $password  # Create a new $HtpasswdFile file with $user/$password info
    [ $Verbose -eq 1 ] && echo && echo "oc create secret generic opfh-htpass-secret --from-file=htpasswd=$HtpasswdFile -n openshift-config"
    oc create secret generic opfh-htpass-secret --from-file=htpasswd=$HtpasswdFile -n openshift-config  # Create an OpenShift secret for saving the htpasswd users info
  else
    echo
    echo "Updating the already existing OpenShift secret (opfh-htpass-secret) with $user info"
    echo "------------------------------------------------------------------------------------------"
    [ $Verbose -eq 1 ] && echo "oc get secret opfh-htpass-secret -ojsonpath={.data.htpasswd} -n openshift-config | base64 --decode > $HtpasswdFile"
    oc get secret opfh-htpass-secret -ojsonpath={.data.htpasswd} -n openshift-config | base64 --decode > $HtpasswdFile  # Save the current Openshift secret config into an htpasswd file
    [ $Verbose -eq 1 ] && echo && echo "htpasswd -Bb $HtpasswdFile $user XXXX"
    htpasswd -Bb $HtpasswdFile $user $password  # Add or Update $user/$password info to the htpasswd file
    [ $Verbose -eq 1 ] && echo && echo "oc create secret generic opfh-htpass-secret --from-file=htpasswd=$HtpasswdFile --dry-run=client -o yaml -n openshift-config | oc replace -f -"
    oc create secret generic opfh-htpass-secret --from-file=htpasswd=$HtpasswdFile --dry-run=client -o yaml -n openshift-config | oc replace -f -  # update the Openshift secret config
  fi

  #-------------------------------------------------------------------------------------------------------------
  # Update the OAuth Identity Providers configuration with the new secret just created/updated above 

    echo
    echo "Pushing the Identity Provider to the Authentication Cluster Operator (oauth) if it doesn't already exist"
    echo "--------------------------------------------------------------------------------------------------------"
  # Get the oauth initial (current) config in JSON format and write it in $OauthInitialConfig file
  [ $Verbose -eq 1 ] && echo "oc get oauth.config.openshift.io/cluster -o json > $OauthInitialConfig"
  oc get oauth.config.openshift.io/cluster -o json > $OauthInitialConfig

  # Test if the "opfh_htpasswd" identity provider is not already defined
  if ! `jq -e -r '.spec.identityProviders' $OauthInitialConfig | grep -q "opfh_htpasswd"`; then

    # Add the definition of the opfh_htpasswd identity provider (after the potential other Identity Providers already defined) and write it in $OauthFinalConfig file
    # (this command below works even if .spec.identityProviders or even .spec does not exist yet in OAuth configuration)
    [ $Verbose -eq 1 ] && echo && echo "jq '.spec.identityProviders[.spec.identityProviders | length] |= .+ {"htpasswd": {"fileData": {"name": "opfh-htpass-secret"}},"mappingMethod": "claim","name": "opfh_htpasswd","type": "HTPasswd"}' $OauthInitialConfig > $OauthFinalConfig"
    jq '.spec.identityProviders[.spec.identityProviders | length] |= .+ {"htpasswd": {"fileData": {"name": "opfh-htpass-secret"}},"mappingMethod": "claim","name": "opfh_htpasswd","type": "HTPasswd"}' $OauthInitialConfig > $OauthFinalConfig

    [ $Verbose -eq 1 ] && echo && echo "oc apply -f $OauthFinalConfig"
    oc apply -f $OauthFinalConfig

  else
    echo "Identity Provider \"opfh_htpasswd\" already defined"
    echo "Doing nothing..."
  fi
}


################################################################################################################
# CHECKING IF PARAMETERS ARE GIVEN OR WE NEED TO ASK QUESTIONS
#

while getopts ":u:p:c:d:s:vh" option; do
  case $option in
    u)
      UserName=$OPTARG
      UserOption=1
    ;;
    p)
      UserPassword=$OPTARG
      UserPasswordOption=1
    ;;
    c)
      CardName=$OPTARG
      CardOption=1
    ;;
    d)
      DockerUser=$OPTARG
      DockerUserOption=1
    ;;
    s)
      DockerPassword=$OPTARG
      DockerPasswordOption=1
    ;;
    v)
      Verbose=1
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
  echo
  echo "========================================================================================================================================="
  while [[ "$UserName" == "" ]]; do
    echo
    echo "What is the OpenShift user name ? (no special character) ? :"
    echo "------------------------------------------------------------"
    read UserName
  done
  echo "========================================================================================================================================="

else
  if [ $Verbose -eq 1 ]; then
    echo
    echo "========================================================================================================================================="
    echo "USER NAME: $UserName"
    echo "========================================================================================================================================="
  fi
fi

UserNamespace="$UserName-project"

################################################################################################################
# ASKING FOR THE USER PASSWORD

if [ $UserPasswordOption -eq 0 ]; then
  echo
  echo "========================================================================================================================================="
  while [[ "$UserPassword" == "" ]]; do
    echo
    echo "What is the $UserName Password ? (no special character) ? :"
    echo "-----------------------------------------------------------"
    read UserPassword
  done
  echo "========================================================================================================================================="

else
  if [ $Verbose -eq 1 ]; then
    echo
    echo "========================================================================================================================================="
    echo "OPENSHIFT USER PASSWORD HAS BEEN PROVIDED FOR $UserName"
    echo "========================================================================================================================================="
  fi
fi


################################################################################################################
# IF NEEDED, ASKING FOR THE DOCKER PASSWORD OF THE USER $DockerUser

if [ $DockerUserOption -eq 1 ]; then

  if [ $Verbose -eq 1 ]; then
    echo
    echo "========================================================================================================================================="
    echo "$DockerUser DOCKER USER HAS BEEN PROVIDED"
    echo "========================================================================================================================================="
  fi

  if [ $DockerPasswordOption -eq 0 ]; then
    echo
    echo "========================================================================================================================================="
    while [[ "$DockerPassword" == "" ]]; do
      echo
      echo "What is the $DockerUser Docker Password ? :"
      echo "-------------------------------------------"
      read DockerPassword
    done
    echo "========================================================================================================================================="

  else
    if [ $Verbose -eq 1 ]; then
      echo
      echo "========================================================================================================================================="
      echo "DOCKER PASSWORD HAS BEEN PROVIDED FOR $DockerUser"
      echo "========================================================================================================================================="
    fi
  fi
fi


################################################################################################################
# CHOOSING THE CARD

TrapCmd="rm -f $TempFile"
touch $TempFile
trap "$TrapCmd" EXIT

NodeList=`oc get nodes | grep worker | awk '{print $1}'`

echo
echo "========================================================================================================================================="
echo "List of OpenCAPI cards seen by the Device Plugin on each node:"
echo "--------------------------------------------------------------"
echo
for Node in $NodeList; do
  echo $Node  | tee -a $TempFile
  oc describe node $Node | sed -n '/Capacity:/,/Allocatable/p' | grep xilinx.com | tee -a $TempFile
  echo
done

echo
echo "List of OpenCAPI cards requests / limits on every node:"
echo "-------------------------------------------------------"
echo "(0 means no card has been allocated yet)"
echo
echo -e "\t\t\t\t requests\tlimits"
for Node in $NodeList; do
  echo $Node
  oc describe node $Node | sed -n '/Allocated resources:/,//p' | grep xilinx.com
  echo
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
echo "========================================================================================================================================="

CardFullName=`grep $CardName $TempFile | awk -F":" '{print $1}' | sed 's/ //g'`

if [ $Verbose -eq 1 ]; then
  echo
  echo "========================================================================================================================================="
  echo "CARD CHOICE                        : $CardName" 
  echo "FULL REFERENCE FOR THE CHOSEN CARD : $CardFullName"
  echo "========================================================================================================================================="
fi


################################################################################################################
# OPENCAPI OR CAPI CASE ?

if `echo $CardFullName | grep -q ocapi`; then
  CardType="Opencapi"

else
  echo "CAPI case not supported"
  exit 1
fi


################################################################################################################
# CARD TYPE

if [ $Verbose -eq 1 ]; then
  echo
  echo "========================================================================================================================================="
  echo "Type of card:"
  echo "-------------"
  echo " --> $CardType"
  echo "========================================================================================================================================="
fi


################################################################################################################
# BUILDING THE YAML FILES (IMAGES+POD) WITH THE GIVEN INFO

UserYAMLDir="$UserYAMLRootDir/$UserName"
#TrapCmd="$TrapCmd; rm -rf $UserYAMLDir"

mkdir -p $UserYAMLDir
#trap "$TrapCmd" EXIT


#===============================================================================================================
# Replacing <USER> / <CARD> by $UserName / $CardName in the yaml definition files

if [ $Verbose -eq 1 ]; then
  echo
  echo "========================================================================================================================================="
  echo "Building the User/Card specific yaml definition files replacing:"
  echo "----------------------------------------------------------------"
  echo "  + <USER>      --> $UserName"
  echo "  + <CARD>      --> $CardName"
  echo "  + <CARD_REF>  --> $CardFullName"
  echo "  + <NAMESPACE> --> $UserNamespace"
  echo
  echo "(from $YamlDir yaml files)"
echo "========================================================================================================================================="
fi

for file in $ImagesDevice_PvYamlFile $ImagesDevice_PvcYamlFile $YamlFile; do
  sed "s!<USER>!$UserName!g; s!<CARD>!$CardName!g; s!<CARD_REF>!$CardFullName!g; s!<NAMESPACE>!$UserNamespace!g" $file > $UserYAMLDir/`basename $file`
done

UserImagesDevice_PvYamlFile="$UserYAMLDir/`basename $ImagesDevice_PvYamlFile`"
UserImagesDevice_PvcYamlFile="$UserYAMLDir/`basename $ImagesDevice_PvcYamlFile`"
UserYamlFile="$UserYAMLDir/`basename $YamlFile`"


################################################################################################################
# BUILDING THE SCRIPT RESPONSIBLE FOR THE NAMESPACE CREATION

cat <<EOF > $UserYAMLDir/$UserNSCreationFile
#!/bin/bash

# Script responsible for creating the User namespace

echo
echo "-----------------------------------------------------------------------------------------------------------------------------------------"
echo "CREATING THE NAMESPACE (PROJECT): $UserNamespace..."
echo "---------------------------------"

echo "oc create namespace $UserNamespace"
oc create namespace $UserNamespace

echo "-----------------------------------------------------------------------------------------------------------------------------------------"
echo
EOF

chmod u+x $UserYAMLDir/$UserNSCreationFile


################################################################################################################
# BUILDING THE SCRIPT RESPONSIBLE FOR THE DOCKER SPECIFIC SECRET CREATION

if [ $DockerUserOption -eq 1 ]; then
  cat <<EOF > $UserYAMLDir/$DockerSecretCreationFile
#!/bin/bash

# Script responsible for creating the Docker Secret and adding it to Default Service Account

echo
echo "-----------------------------------------------------------------------------------------------------------------------------------------"
echo "CREATING THE SECRET docker-$DockerUser FOR PROJECT $UserNamespace and adding it to Default Service Account..."
echo "--------------------------------------------------------------------------------------------------------"

echo "oc -n $UserNamespace create secret docker-registry docker-$DockerUser \\\\"
echo "   --docker-server=docker.io  \\\\"
echo "   --docker-username=$DockerUser \\\\"
echo "   --docker-password=XXXXXXXXX"
#echo "   --docker-password=XXXXXXXXX \\\\"
#echo "   --docker-email=fabrice_moyen@fr.ibm.com"

oc -n $UserNamespace create secret docker-registry docker-$DockerUser \
   --docker-server=docker.io  \
   --docker-username=$DockerUser \
   --docker-password=$DockerPassword
#   --docker-password=$DockerPassword \
#   --docker-email=fabrice_moyen@fr.ibm.com

echo
echo "oc -n $UserNamespace secrets link default docker-$DockerUser --for=pull"
sleep 2 # Giving some time for the default Service Account to be available for update
oc -n $UserNamespace secrets link default docker-$DockerUser --for=pull
echo "-----------------------------------------------------------------------------------------------------------------------------------------"

EOF

  chmod u+x $UserYAMLDir/$DockerSecretCreationFile
fi


################################################################################################################
# BUILDING THE SCRIPT THAT WILL BE RESPONSIBLE FOR DELETING ALL USER RESOURCES (PV, PVC, POD, NAMESPACE)

cat <<EOF > $UserYAMLDir/$UserResourcesDeleteScript
#!/bin/bash

# Script that will delete all resources for the user $UserName (User, Identity, Htpasswd info, PV, PVC, POD, Namespace)

echo
echo "-----------------------------------------------------------------------------------------------------------------------------------------"
echo "DELETING RESOURCES FOR USER $UserName..."
echo
echo "Warning: PVC deletion may take a minute as it needs to wait for Pod complete deletion"
echo "         Namespace deletion is also not instantaneous"
echo "-----------------------------------------------------------------------------------------------------------------------------------------"

# Removing the RBAC User Role
echo
echo "-----------------------------------------------------------------------------------------------------------------------------------------"
echo "oc adm policy remove-role-from-user $RBACUserRole $UserName -n $UserNamespace"
oc adm policy remove-role-from-user $RBACUserRole $UserName -n $UserNamespace

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
echo "oc get secret opfh-htpass-secret -ojsonpath={.data.htpasswd} -n openshift-config | base64 --decode > $HtpasswdFile"
oc get secret opfh-htpass-secret -ojsonpath={.data.htpasswd} -n openshift-config | base64 --decode > $HtpasswdFile  # Save the current Openshift secret config into an htpasswd file

echo
echo "htpasswd -D $HtpasswdFile $UserName"
htpasswd -D $HtpasswdFile $UserName  # Delete $user info from the htpasswd file

echo
echo "oc create secret generic opfh-htpass-secret --from-file=htpasswd=$HtpasswdFile --dry-run=client -o yaml -n openshift-config | oc replace -f -"
oc create secret generic opfh-htpass-secret --from-file=htpasswd=$HtpasswdFile --dry-run=client -o yaml -n openshift-config | oc replace -f -  # update the Openshift secret config

echo
echo "oc delete user $UserName"
oc delete user $UserName

echo
echo "oc delete identity opfh_htpasswd:$UserName"
oc delete identity opfh_htpasswd:$UserName

# Deleting the user Yaml directory
echo
echo "-----------------------------------------------------------------------------------------------------------------------------------------"
echo "Deleting $UserYAMLDir directory"
echo "rm -rf $UserYAMLDir"
rm -rf $UserYAMLDir

echo "-----------------------------------------------------------------------------------------------------------------------------------------"
echo
EOF

chmod u+x $UserYAMLDir/$UserResourcesDeleteScript

echo
echo "========================================================================================================================================="
echo "LET'S DO THE JOB:"
echo "-----------------"

################################################################################################################
# CREATING THE USER THANKS TO AN HTPASSWD IDENTITY PROVIDER

if [ $Verbose -eq 1 ]; then
  echo
  echo "-----------------------------------------------------------------------------------------------------------------------------------------"
  echo "CREATING THE USER $UserName THANKS TO AN HTPASSWD IDENTITY PROVIDER"
  echo "-------------------------------------------------------------------------------"
fi

Add_User_Definition $UserName $UserPassword

[ $Verbose -eq 1 ] && echo "-----------------------------------------------------------------------------------------------------------------------------------------"



################################################################################################################
# CREATING THE NAMESPACE $UserNamespace thanks to $UserYAMLDir/$UserNSCreationFile bash script

if [ $Verbose -eq 1 ]; then
  $UserYAMLDir/$UserNSCreationFile
else
  $UserYAMLDir/$UserNSCreationFile >/dev/null
fi


################################################################################################################
# IF NEEDED, CREATING A SECRET TO PULL DOCKER IMAGE WITH $DockerUser ID
# (THIS TO OVERCOME GLOBAL LIMITATIONS)

if [ $DockerUserOption -eq 1 ]; then
  if [ $Verbose -eq 1 ]; then
    $UserYAMLDir/$DockerSecretCreationFile
  else
    $UserYAMLDir/$DockerSecretCreationFile >/dev/null
  fi
fi


################################################################################################################
# DISPLAYING THE USER YAML DEFINITION FILES AND STARTING THE POD

if [ $Verbose -eq 1 ]; then
  echo
  echo "========================================================================================================================================="
  echo "CREATING THE POD USING THESE DEFINITION YAML FILES:"
  echo "---------------------------------------------------"
  echo "  Binary Image PV creation :                 $UserImagesDevice_PvYamlFile"
  echo "  Binary Image PVC creation :                $UserImagesDevice_PvcYamlFile"
  echo "  CAPIapp deployment creation:               $UserYamlFile"
  echo "-----------------------------------------------------------------------------------------------------------------------------------------"
fi

for i in $UserImagesDevice_PvYamlFile $UserImagesDevice_PvcYamlFile $UserYamlFile; do
  echo 
  echo "oc create -f $i"
  if ! oc create -f $i 2> $TempFile; then
    if grep -q "already exists" $TempFile; then
      echo "  --> already exists"
    else
      cat $TempFile
    fi
  fi
done

sleep 2 # Giving some time for resources to be here



################################################################################################################
# ADDING RBAC ROLE FOR USER TO ACCESS THE NAMESPACE

if [ $Verbose -eq 1 ]; then
  echo
  echo "========================================================================================================================================="
  echo "ADDING \"$RBACUserRole\" RBAC ROLE FOR THE USER $UserName TO ACCESS THE NAMESPACE $UserNamespace"
  echo "------------------------------------------------------------------------------------------------------------------------"
fi

echo
echo "oc adm policy add-role-to-user $RBACUserRole $UserName -n $UserNamespace"
echo "     (a \"User not found\" warning is normal)"
oc adm policy add-role-to-user $RBACUserRole $UserName -n $UserNamespace

echo "========================================================================================================================================="


################################################################################################################
# DISPLAYING NEWLY CREATED RESOURCES INFO

if [ $Verbose -eq 1 ]; then
  echo
  echo "========================================================================================================================================="
  echo "HERUNDER INFO ABOUT THE NEWLY CRATED RESOURCES:"
  echo "-----------------------------------------------"
  echo 
  echo "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
  echo "oc describe namespace/$UserNamespace" 
  oc describe namespace/$UserNamespace
  echo
  echo "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
  echo "oc -n $UserNamespace get all" 
  oc -n $UserNamespace get all 
  echo
  echo "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
  echo "oc -n $UserNamespace get pv/images-$UserName pvc/images-$UserName-pvc" 
  oc -n $UserNamespace get pv/images-$UserName pvc/images-$UserName-pvc 
  echo "========================================================================================================================================="
fi


################################################################################################################
# DISPLAYING USEFUL COMMANDS TO USE THE NEWLY CREATED RESOURCES

MyPod="pod/`oc -n $UserNamespace get pod --no-headers=true | awk '{print $1}'`"

echo
echo "========================================================================================================================================="
echo "USEFUL COMMANDS TO ACCESS THE NEWLY CREATED RESOURCES:"
echo "---------------------------------------------------"
echo 
echo "  oc -n $UserNamespace rsh $MyPod" 
echo "========================================================================================================================================="

################################################################################################################
# DISPLAYING THE BASH SCRIPT GENERATED FOR DELETING THE USER RESOURCES

echo
echo "========================================================================================================================================="
echo "SCRIPTS TO USE IN ORDER TO DELETE THE USER RESOURCES (PV, PVC, POD, NAMESPACE):"
echo "-------------------------------------------------------------------------------"
echo "2 choices:"
echo "---------:"
echo
echo "  $UserYAMLDir/$UserResourcesDeleteScript"
echo "    --> Dedicated script for $UserName user (This script will also delete $UserYAMLDir directory)"
echo
echo "  $RealPath/delete_UserResources.bash -u $UserName -d $UserYAMLDir"
echo "    --> generic script so you need to provide the Username and the directory (where the YAML files and scripts for this user are located) if you want to delete it"
echo "========================================================================================================================================="

echo
