#!/bin/bash

################################################################################################################
# Bash script used to create an OpenShift user and all his needed resources to give him access to an OpenCAPI card
# Author: Fabrice MOYEN (IBM)

# To do its job, this script needs to know:
#  - the user name and the password that will be used by the user to connect to the OpenShift cluster
#  - the type of card requested (like ad9h3)
#  - Optionally a docker account (and his password) to be used to pull docker images (this in order to bypass docker pull rates limits)
#
# The script will then:
#  - configure the cluster to prohibit any user from creating namespaces (projects)
#  - generate the yaml definition files needed to create the user resources (namespace, POD, etc)
#  - generate a script that may be used to delete all user resources when not needed anymore
#  - create the user (today using an htpasswd ID provider)
#  - create the namespace (project) for the user
#  - create the PV/PVC pointing to the user binaries directory
#  - create the POD/container with access to the volume hosting the user partial binaries
#  - give the user access to the namespace with the "view" RBAC Role
#  - create a pod-shell role (allowing to connect to a pod console) and give it to the user (so the user will have "view + pod-shell" role
#
# Parameters to adapt to the environment once:
#  - UserYAMLRootDir : where all the YAML/scripts files needed to generate the user environment (and to delete it) will be stored


################################################################################################################
# VARIABLES

#---------------------------------------------------------------------------------------------------------------
# Variables you may want to change

# Root directory where to store the user YAML & bash files to create and delete the user's resources
UserYAMLRootDir=/tmp

# The name used for the htpasswd Identity Provider we're going to create (Warning: once created, you will need to manually delete it if you decide to change this variable afterwards)
IDProviderName="opfh-htpasswd"

#---------------------------------------------------------------------------------------------------------------
# Variables you don't need to change

RealPath=`realpath $0`
RealPath=`dirname $RealPath`

YamlDir="$RealPath/OPENCAPI-user-device_requested"

YamlFile=`ls $YamlDir/OPENCAPI-*-deploy.yaml 2>/dev/null | head -1`
ImagesDevice_PvYamlFile=`ls $YamlDir/images-user-pv.yaml 2>/dev/null`
ImagesDevice_PvcYamlFile=`ls $YamlDir/images-user-pvc.yaml 2>/dev/null`

UserResourcesDeleteScript="deleteUserResources.bash"
UserNSCreationFile="createUserNamespace.bash"
DockerSecretCreationFile="createDockerSecret.bash"

# Giving only "view" role to user (so he cannot create a new POD, or delete the POD, etc... but also cannot connect to the POD terminal, and that's an issue)
# (we'll create for the project a new "pod-shell" role that will allow the user to "oc rsh" to the POD or use the OCP GUI to connect to the POD terminal. That's not allowed by the "view" role)
RBACUserRole="view"

SecretName="${IDProviderName}-secret"

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

Verbose=0

TempDir=/tmp
TempFile=$TempDir/add_UserResources.tmp
OauthInitialConfig=$TempDir/oauth_initial.json
OauthFinalConfig=$TempDir/oauth_final.json
HtpasswdFile=$TempDir/users.htpasswd


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
  echo "`basename $0` -u Fabrice -p XXXX -c ad9h3"
  echo "`basename $0` -u Fabrice -c ad9h3 -d fmoyen"
  echo "`basename $0` -u Fabrice -p XXXX -c ad9h3 -d fmoyen -s YYYY -v"
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

  if ! oc get secret $SecretName -n openshift-config > /dev/null 2>&1; then 
    echo
    echo "Creating a new OpenShift secret ($SecretName) with $user info:"
    echo "--------------------------------------------------------------------------"
    [ $Verbose -eq 1 ] && echo "htpasswd -c -Bb $HtpasswdFile $user XXXX"
    htpasswd -c -Bb $HtpasswdFile $user $password  # Create a new $HtpasswdFile file with $user/$password info
    [ $Verbose -eq 1 ] && echo && echo "oc create secret generic $SecretName --from-file=htpasswd=$HtpasswdFile -n openshift-config"
    oc create secret generic $SecretName --from-file=htpasswd=$HtpasswdFile -n openshift-config  # Create an OpenShift secret for saving the htpasswd users info
  else
    echo
    echo "Updating the already existing OpenShift Secret entry ($SecretName) with $user info:"
    echo "----------------------------------------------------------------------------------------------"
    [ $Verbose -eq 1 ] && echo "oc get secret $SecretName -ojsonpath={.data.htpasswd} -n openshift-config | base64 --decode > $HtpasswdFile"
    oc get secret $SecretName -ojsonpath={.data.htpasswd} -n openshift-config | base64 --decode > $HtpasswdFile  # Save the current Openshift secret config into an htpasswd file
    [ $Verbose -eq 1 ] && echo && echo "htpasswd -Bb $HtpasswdFile $user XXXX"
    htpasswd -Bb $HtpasswdFile $user $password  # Add or Update $user/$password info to the htpasswd file
    [ $Verbose -eq 1 ] && echo && echo "oc create secret generic $SecretName --from-file=htpasswd=$HtpasswdFile --dry-run=client -o yaml -n openshift-config | oc replace -f -"
    oc create secret generic $SecretName --from-file=htpasswd=$HtpasswdFile --dry-run=client -o yaml -n openshift-config | oc replace -f -  # update the Openshift secret config
  fi

  #-------------------------------------------------------------------------------------------------------------
  # Update the OAuth Identity Providers configuration with the new secret just created/updated above 

    echo
    echo "Pushing the Identity Provider to the Authentication Cluster Operator (oauth) if it doesn't already exist:"
    echo "---------------------------------------------------------------------------------------------------------"
  # Get the oauth initial (current) config in JSON format and write it in $OauthInitialConfig file
  [ $Verbose -eq 1 ] && echo "oc get oauth.config.openshift.io/cluster -o json > $OauthInitialConfig"
  oc get oauth.config.openshift.io/cluster -o json > $OauthInitialConfig

  # Test if the $IDProviderName identity provider is not already defined
  if ! `jq -e -r '.spec.identityProviders' $OauthInitialConfig | grep -q $IDProviderName`; then

    # Add the definition of the $IDProviderName identity provider (after the potential other Identity Providers already defined) and write it in $OauthFinalConfig file
    # (this command below works even if .spec.identityProviders or even .spec does not exist yet in OAuth configuration)
    [ $Verbose -eq 1 ] && echo && echo "jq '.spec.identityProviders[.spec.identityProviders | length] |= .+ {\"htpasswd\": {\"fileData\": {\"name\": \"$SecretName\"}},\"mappingMethod\": \"claim\",\"name\": \"$IDProviderName\",\"type\": \"HTPasswd\"}' $OauthInitialConfig > $OauthFinalConfig"

    CMD="jq '.spec.identityProviders[.spec.identityProviders | length] |= .+ {\"htpasswd\": {\"fileData\": {\"name\": \"$SecretName\"}},\"mappingMethod\": \"claim\",\"name\": \"$IDProviderName\",\"type\": \"HTPasswd\"}' $OauthInitialConfig > $OauthFinalConfig"
    eval $CMD

    [ $Verbose -eq 1 ] && echo && echo "oc apply -f $OauthFinalConfig" && echo "(The Oauth Cluster Operator may take about 5 minutes to apply the changes)"
    oc apply -f $OauthFinalConfig

  else
    echo "Identity Provider \"$IDProviderName\" already defined"
    echo "Doing nothing..."
  fi
}


#===============================================================================================================
# We need to remove the self-provisioner cluster role from the group system:authenticated:oauth
# in order to disallow any OpenShift user to have default permission to create a new project

function Remove_selfprovisioner
{
  echo
  echo "Prohibiting any standard OpenShift user from creating a new project:"
  echo "--------------------------------------------------------------------" 

  if oc describe clusterrolebinding.rbac self-provisioners | grep -q "system:authenticated:oauth"; then
    [ $Verbose -eq 1 ] && echo "oc patch clusterrolebinding.rbac self-provisioners -p '{\"subjects\": null}'"
    oc patch clusterrolebinding.rbac self-provisioners -p '{"subjects": null}'

  else
    echo "The self-provisioner cluster role has already been removed from the group system:authenticated:oauth"
    echo "Doing nothing..."
  fi
}


#===============================================================================================================
# We create a "pod-shell" role for the project and add this role to the user; this in order to allow the user to "oc rsh" the POD or connect to the POD terminal using the GUI

function Create_podshell
{
  local user=$1
  local project=$2

  # Creating the pod-shell role for the $project
  echo
  echo "Creating the \"pod-shell\" role for the $project project:"
  echo "---------------------------------------------------------"

  if [ $Verbose -eq 1 ]; then
    echo "  cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: $project
  name: pod-shell
rules:
- apiGroups: [""]
  resources: ["pods/exec"]
  verbs: ["create", "get"]
EOF
"
  fi

  cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: $project
  name: pod-shell
rules:
- apiGroups: [""]
  resources: ["pods/exec"]
  verbs: ["create", "get"]
EOF

  # Adding the $project role "pod-shell" to the $user
  echo
  echo "Adding the \"pod-shell\" role to the $user user ('User not found' warning is normal):"
  echo "---------------------------------------------------------------------------------------"
  [ $Verbose -eq 1 ] && echo "oc adm policy add-role-to-user pod-shell $user --role-namespace=$project -n $project"
  oc adm policy add-role-to-user pod-shell $user --role-namespace=$project -n $project
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
# REAL MAIN STARTS HERE

clear
echo "========================================================================================================================================="


################################################################################################################
# ASKING FOR THE USER NAME

if [ $UserOption -eq 0 ]; then
  while [[ "$UserName" == "" ]]; do
    echo
    echo "What is the OpenShift user name ? (no special character) ? :"
    echo "------------------------------------------------------------"
    read UserName
  done

else
  if [ $Verbose -eq 1 ]; then
    echo
    echo "User Name: $UserName"
  fi
fi

UserNamespace="$UserName-project"

################################################################################################################
# ASKING FOR THE USER PASSWORD

if [ $UserPasswordOption -eq 0 ]; then
  echo
  while [[ "$UserPassword" == "" ]]; do
    echo
    echo "What is the $UserName Password ? (no special character) ? :"
    echo "-----------------------------------------------------------"
    read UserPassword
  done

else
  if [ $Verbose -eq 1 ]; then
    echo "OpenShift user password has been provided for $UserName"
  fi
fi


################################################################################################################
# IF NEEDED, ASKING FOR THE DOCKER PASSWORD OF THE USER $DockerUser

if [ $DockerUserOption -eq 1 ]; then

  if [ $Verbose -eq 1 ]; then
    echo
    echo "$DockerUser docker user has been provided"
  fi

  if [ $DockerPasswordOption -eq 0 ]; then
    while [[ "$DockerPassword" == "" ]]; do
      echo
      echo "What is the $DockerUser Docker Password ? :"
      echo "-------------------------------------------"
      read DockerPassword
    done

  else
    if [ $Verbose -eq 1 ]; then
      echo "Docker password has been provided for $DockerUser"
    fi
  fi
fi

echo
echo "All user and password settings have been provided"
echo "========================================================================================================================================="


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
  echo "Card choice                        : $CardName" 
  echo "Full reference for the chosen card : $CardFullName"
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
  echo "Type of card:"
  echo "-------------"
  echo " --> $CardType"
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
  echo "Building the User/Card specific yaml definition files:"
  echo "------------------------------------------------------"
  echo "Replacing..."
  echo "  + <USER>      --> $UserName"
  echo "  + <CARD>      --> $CardName"
  echo "  + <CARD_REF>  --> $CardFullName"
  echo "  + <NAMESPACE> --> $UserNamespace"
  echo
  echo "from $YamlDir yaml files"
fi

for file in $ImagesDevice_PvYamlFile $ImagesDevice_PvcYamlFile $YamlFile; do
  sed "s!<USER>!$UserName!g; s!<CARD>!$CardName!g; s!<CARD_REF>!$CardFullName!g; s!<NAMESPACE>!$UserNamespace!g" $file > $UserYAMLDir/`basename $file`
done

UserImagesDevice_PvYamlFile="$UserYAMLDir/`basename $ImagesDevice_PvYamlFile`"
UserImagesDevice_PvcYamlFile="$UserYAMLDir/`basename $ImagesDevice_PvcYamlFile`"
UserYamlFile="$UserYAMLDir/`basename $YamlFile`"

[ $Verbose -eq 1 ] && echo "========================================================================================================================================="


################################################################################################################
# BUILDING THE SCRIPT RESPONSIBLE FOR THE NAMESPACE CREATION

if [ $Verbose -eq 1 ]; then
  echo
  echo "========================================================================================================================================="
  echo "Building the script responsible for the namespace creation:"
  echo "-----------------------------------------------------------"
  echo "  --> $UserYAMLDir/$UserNSCreationFile"
fi

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

if [ $Verbose -eq 1 ]; then
  echo
  echo "========================================================================================================================================="
  echo "Building the script responsible for the docker specific secret creation:"
  echo "------------------------------------------------------------------------"
  echo "  --> $UserYAMLDir/$DockerSecretCreationFile"
fi

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

if [ $Verbose -eq 1 ]; then
  echo
  echo "========================================================================================================================================="
  echo "Building the script that will be responsible for deleting all user resources (PV, PVC, POD, NAMESPACE, USER, etc):"
  echo "------------------------------------------------------------------------------------------------------------------"
  echo "  --> $UserYAMLDir/$UserResourcesDeleteScript"
fi

cat <<EOF > $UserYAMLDir/$UserResourcesDeleteScript
#!/bin/bash

# Script that will delete all resources for the user $UserName (User, Identity, Htpasswd info, PV, PVC, POD, Namespace)

clear
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
echo
echo "-----------------------------------------------------------------------------------------------------------------------------------------"
echo "Deleting $UserYAMLDir directory"
echo "rm -rf $UserYAMLDir"
rm -rf $UserYAMLDir

echo "========================================================================================================================================="
echo
EOF

chmod u+x $UserYAMLDir/$UserResourcesDeleteScript


################################################################################################################
# CLUSTER CONFIGURATION MODIFICATIONS START HERE

echo
echo "========================================================================================================================================="
echo "NOW LET'S MAKE THE NECESSARY CHANGES TO THE CLUSTER:"
echo "----------------------------------------------------"


################################################################################################################
# DISALLOW ANY OPENSHIFT USER TO HAVE DEFAULT PERMISSION TO CREATE A NEW PROJECT

Remove_selfprovisioner

################################################################################################################
# CREATING THE USER THANKS TO AN HTPASSWD IDENTITY PROVIDER

Add_User_Definition $UserName $UserPassword


################################################################################################################
# CREATING THE NAMESPACE $UserNamespace thanks to $UserYAMLDir/$UserNSCreationFile bash script


if [ $Verbose -eq 1 ]; then
  $UserYAMLDir/$UserNSCreationFile
else
  echo
  echo "Creating the $UserNamespace namespace:"
  echo "--------------------------------------"
  $UserYAMLDir/$UserNSCreationFile >/dev/null
  echo "Done"
fi


################################################################################################################
# IF NEEDED, CREATING A SECRET TO PULL DOCKER IMAGE WITH $DockerUser ID
# (THIS TO OVERCOME GLOBAL LIMITATIONS)

if [ $DockerUserOption -eq 1 ]; then
  if [ $Verbose -eq 1 ]; then
    $UserYAMLDir/$DockerSecretCreationFile
  else
    echo
    echo "Creating an OpenShift Secret to pull docker images with $DockerUser ID:"
    echo "-----------------------------------------------------------------------"
    $UserYAMLDir/$DockerSecretCreationFile >/dev/null
    echo "Done"
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

echo
echo "Creating the PV, PVC and POD resources:"
echo "---------------------------------------"

for i in $UserImagesDevice_PvYamlFile $UserImagesDevice_PvcYamlFile $UserYamlFile; do
  [ $Verbose -eq 1 ] && echo && echo "oc create -f $i"
  if ! oc create -f $i 2> $TempFile; then
    if grep -q "already exists" $TempFile; then
      echo "  $i --> already exists"
    else
      cat $TempFile
    fi
  fi
done

sleep 2 # Giving some time for resources to be here


################################################################################################################
# ADDING RBAC ROLE FOR USER TO ACCESS THE NAMESPACE

echo
echo "Adding \"$RBACUserRole\" RBAC role for the user $UserName to access the $UserNamespace namespace ('User not found' warning is normal) :"
echo "------------------------------------------------------------------------------------------------------------------------"

[ $Verbose -eq 1 ] && echo && echo "oc adm policy add-role-to-user $RBACUserRole $UserName -n $UserNamespace"
oc adm policy add-role-to-user $RBACUserRole $UserName -n $UserNamespace


################################################################################################################
# CREATING THE pod-shell ROLE FOR THE PROJECT AND GIVING THIS ROLE TO THE USER

Create_podshell $UserName $UserNamespace

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
echo "USEFUL CLI COMMAND TO ACCESS THE NEWLY CREATED RESOURCES:"
echo "---------------------------------------------------------"
echo 
echo "  oc -n $UserNamespace rsh $MyPod" 
echo "========================================================================================================================================="


################################################################################################################
# DISPLAYING THE BASH SCRIPT GENERATED FOR DELETING THE USER RESOURCES

echo
echo "========================================================================================================================================="
echo "SCRIPTS TO USE IN ORDER TO DELETE THE CREATED USER RESOURCES (PV, PVC, POD, NAMESPACE, USER):"
echo "---------------------------------------------------------------------------------------------"
echo "2 choices:"
echo "----------"
echo
echo "  $UserYAMLDir/$UserResourcesDeleteScript"
echo "    --> Dedicated script for $UserName user (This script will also delete $UserYAMLDir directory)"
echo
echo "  $RealPath/delete_UserResources.bash -u $UserName -c $CardName -d $UserYAMLDir"
echo "    --> Generic script. That's why you need to provide the user name, the card name and (if you want to delete it) the directory where the YAML/scripts files used to create this user are located"
echo "========================================================================================================================================="


################################################################################################################
# WARNING OUTPUT

echo
echo "========================================================================================================================================="
echo "WARNING:"
echo "--------"
echo
echo "The OpenShift cluster (the \"oauth\" authentication cluster operator) could take a minute or two to validate the creation of the new user."
echo "The connection with this user will fail during this time. It is then 'urgent' to wait ;-P"
echo "========================================================================================================================================="

echo
