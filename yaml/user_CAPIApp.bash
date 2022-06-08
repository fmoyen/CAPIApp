#!/bin/bash

clear


################################################################################################################
# Bash script used when a standard user wants a POD with an OpenCAPI card
# Author: Fabrice MOYEN (IBM)

# We need to:
#  - ask for the user name
#  - generate the namespace (project) with the user name
#  - generate the POD yaml definition file (project, name, etc)
#  - generate the PV/PVC pointing to the user binaries directory
#  - create the POD/container with access to the volume hosting the user partial binaries
#
# We need to be able to provide all these info thanks to parameters (without any interactive question)
#
# We need to create a script to delete User PV, PVC and deployment


################################################################################################################
# VARIABLES

UserName=""
TempFile="/tmp/user_CAPIapp.tmp"
UserYAMLRootDir=/tmp
UserResourcesDeleteScript="resourcesDelete.bash"
CardName="nul"
ImagesDevice_PvYamlFile=""
ImagesDevice_PvcYamlFile=""
UserNSCreationFile="userNamespaceCreation.bash"
MopSecretCreationFile="mopDockerSecretCreation.bash"
UserNamespace=""
YamlRootDir=""
SubDir="nul"
YamlDir=""
CardType=""
UserOption=0
CardOption=0
DockerPasswordOption=0
DockerPassword=""

# Delete the next line to unset 'Montpellier' variable if you are not at Montpellier 
Montpellier=1


################################################################################################################
# FUNCTIONS
#

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
  echo "  + -c <Card Name> : to give the card type you want"

  if [ ! -z ${Montpellier+x} ]; then
    echo
    echo "  + -p <Docker Personal Password> : Specific to IBM Montpellier (Docker fmoyen password to download Docker images)"
  fi

  echo
  echo "  + -h : shows this usage info"
  echo
  echo "Example:"
  echo "--------"
  echo "`basename $0`"
  echo "`basename $0` -u Fabrice"
  echo "`basename $0` -u Fabrice -c ad9h3"
  echo
  exit 0
}


################################################################################################################
# CHECKING IF PARAMETERS ARE GIVEN OR WE NEED TO ASK QUESTIONS
#

while getopts ":u:c:p:h" option; do
  case $option in
    u)
      UserName=$OPTARG
      UserOption=1
    ;;
    c)
      CardName=$OPTARG
      CardOption=1
    ;;
    p)
      DockerPassword=$OPTARG
      DockerPasswordOption=1
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
# MONTPELLIER OR NOT ?

if [ ! -z ${Montpellier+x} ]; then
  echo
  echo "========================================================================================================================================="
  echo "MONTPELLIER CLUSTER"
  echo "========================================================================================================================================="
fi


################################################################################################################
# ASKING FOR THE USER NAME

if [ $UserOption -eq 0 ]; then
  while [[ "$UserName" == "" ]]; do
    echo
    echo "What is your name ? (no special character) ? :"
    echo "----------------------------------------------"
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
# SPECIFIC TO IBM MONTPELLIER: ASKING FOR THE DOCKER fmoyen PASSWORD

if [ ! -z ${Montpellier+x} ]; then
  if [ $DockerPasswordOption -eq 0 ]; then
    while [[ "$DockerPassword" == "" ]]; do
      echo
      echo "What is the Docker fmoyen Password ? :"
      echo "--------------------------------------"
      read DockerPassword
    done

  else
    echo
    echo "========================================================================================================================================="
    echo "DOCKER PASSWORD HAS BEEN PROVIDED"
    echo "========================================================================================================================================="
  fi
fi


################################################################################################################
# CHOOSING THE CARD

TrapCmd="rm -f $TempFile"

if [ -z ${Montpellier+x} ]; then    # NOT Montpellier so manually giving the list of available cards in the cluster
  echo
  echo "List of OpenCAPI cards allocatable:"
  echo "-----------------------------------"
  cat <<EOF | tee $TempFile
xilinx.com/fpga-ad9h3_ocapi-0x0667
xilinx.com/fpga-ad9h7_ocapi-0x0666
EOF

else    # Montpellier, so directely getting the list of cards from the only IC922 worker node
  Node="hawk08"
  echo
  echo "List of OpenCAPI cards seen by the Device Plugin on $Node:"
  echo "-----------------------------------------------------------"
  oc describe node $Node | sed -n '/Capacity:/,/Allocatable/p' | grep xilinx | tee $TempFile
  trap "$TrapCmd" EXIT

  echo
  echo "List of OpenCAPI cards requests / limts on $Node:"
  echo "--------------------------------------------------"
  echo "(0 means no card has been allocated yet)"
  echo -e "\t\t\t\t requests\tlimits"
  oc describe node $Node | sed -n '/Allocated resources:/,//p' | grep xilinx
fi

if [ $CardOption -eq 0 ]; then
  while ! grep -q $CardName $TempFile; do
    echo
    echo "Please choose between the following card type:"
    echo "----------------------------------------------"
    cat $TempFile | awk -F"-" '{print $2}' | awk -F"_" '{print $1}'
    echo -e "?: \c"
    read CardName
  done
fi

CardFullName=`grep $CardName $TempFile | awk -F":" '{print $1}' | sed 's/ //g'`
echo
echo "========================================================================================================================================="
echo "CARD CHOICE                       : $CardName" 
echo "FULL REFERENCE OF THE CHOSEN CARD : $CardFullName"
echo "========================================================================================================================================="


################################################################################################################
# OPENCAPI CASE

if `echo $CardFullName | grep -q ocapi`; then
  CardType="Opencapi"

  YamlRootDir="OPENCAPI-user-device_requested/current"
  SubDir="OCAPI_requested"
  YamlDir=$YamlRootDir/$SubDir

  YamlFile=`ls $YamlDir/OPENCAPI-*-deploy.yaml 2>/dev/null | head -1`

  ImagesDevice_PvYamlFile=`ls $YamlDir/images-user-pv.yaml 2>/dev/null`
  ImagesDevice_PvcYamlFile=`ls $YamlDir/images-user-pvc.yaml 2>/dev/null`


################################################################################################################
# CAPI CASE

else
  echo "CAPI case not supported"
  exit 1
fi


################################################################################################################
# CARD TYPE

echo
echo "Type of card:"
echo "-------------"
echo " --> $CardType"


################################################################################################################
# BUILDING THE YAML FILES (IMAGES+POD) WITH THE GIVEN INFO

UserYAMLDir="$UserYAMLRootDir/$UserName"
#TrapCmd="$TrapCmd; rm -rf $UserYAMLDir"

mkdir -p $UserYAMLDir
#trap "$TrapCmd" EXIT


#===============================================================================================================
# Replacing <USER> / <CARD> by $UserName / $CardName in the yaml definition files

echo
echo "Building the User/Card specific yaml definition files replacing:"
echo "----------------------------------------------------------------"
echo "  + <USER>      --> $UserName"
echo "  + <CARD>      --> $CardName"
echo "  + <CARD_REF>  --> $CardFullName"
echo "  + <NAMESPACE> --> $UserNamespace"
echo
echo "(from $YamlDir yaml files)"

for file in $ImagesDevice_PvYamlFile $ImagesDevice_PvcYamlFile $YamlFile; do
  sed "s!<USER>!$UserName!g; s!<CARD>!$CardName!g; s!<CARD_REF>!$CardFullName!g; s!<NAMESPACE>!$UserNamespace!g" $file > $UserYAMLDir/`basename $file`
done

UserImagesDevice_PvYamlFile="$UserYAMLDir/`basename $ImagesDevice_PvYamlFile`"
UserImagesDevice_PvcYamlFile="$UserYAMLDir/`basename $ImagesDevice_PvcYamlFile`"
UserYamlFile="$UserYAMLDir/`basename $YamlFile`"


#===============================================================================================================
# Building the script responsible for the namespace creation

cat <<EOF > $UserYAMLDir/$UserNSCreationFile
#!/bin/bash

# Script responsible for creating the User namespace

echo
echo "========================================================================================================================================="
echo "CREATING THE NAMESPACE (PROJECT): $UserNamespace..."
echo "-----------------------------------------------------------------------------------------------------------------------------------------"

echo "oc create namespace $UserNamespace"
oc create namespace $UserNamespace

echo "========================================================================================================================================="
echo
EOF

chmod u+x $UserYAMLDir/$UserNSCreationFile


#===============================================================================================================
# Building the script responsible for the IBM Montpellier specific Secret creation

if [ ! -z ${Montpellier+x} ]; then
  cat <<EOF > $UserYAMLDir/$MopSecretCreationFile
#!/bin/bash

# Script responsible for creating the Secret specific to IBM Montpellier

echo
echo "========================================================================================================================================="
echo "CREATING THE SECRET docker-fmoyen FOR PROJECT $UserNamespace and adding it to Default Service Account..."
echo "-----------------------------------------------------------------------------------------------------------------------------------------"

echo "oc -n $UserNamespace create secret docker-registry docker-fmoyen \\\\"
echo "   --docker-server=docker.io  \\\\"
echo "   --docker-username=fmoyen \\\\"
echo "   --docker-password=XXXXXXXXX \\\\"
echo "   --docker-email=fabrice_moyen@fr.ibm.com"

oc -n $UserNamespace create secret docker-registry docker-fmoyen \
   --docker-server=docker.io  \
   --docker-username=fmoyen \
   --docker-password=$DockerPassword \
   --docker-email=fabrice_moyen@fr.ibm.com

echo
echo "oc -n $UserNamespace secrets link default docker-fmoyen --for=pull"
sleep 2 # Giving some time for the default Service Account to be available for update
oc -n $UserNamespace secrets link default docker-fmoyen --for=pull

EOF

  chmod u+x $UserYAMLDir/$MopSecretCreationFile
fi


#===============================================================================================================
# Building the script that will be responsible for deleting all user resources (PV, PVC, POD, Namespace)

cat <<EOF > $UserYAMLDir/$UserResourcesDeleteScript
#!/bin/bash

# Script that will delete all resources for the user $UserName (PV, PVC, POD, Namespace)

echo
echo "========================================================================================================================================="
echo "DELETING RESOURCES FOR USER $UserName..."
echo
echo "Warning: PVC deletion may take a minute as it needs to wait for Pod complete deletion"
echo "         Namespace deletion is also not instantaneous"
echo "-----------------------------------------------------------------------------------------------------------------------------------------"

# Deleting the Deployment (with the ReplicatSet and the Pod coming with it)
echo
echo "oc -n $UserNamespace delete deployment.apps/oc-$UserName-$CardName"
oc -n $UserNamespace delete deployment.apps/oc-$UserName-$CardName

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
echo "Deleting $UserYAMLDir directory"
echo "rm -rf $UserYAMLDir"
rm -rf $UserYAMLDir

echo "========================================================================================================================================="
echo
EOF

chmod u+x $UserYAMLDir/$UserResourcesDeleteScript


################################################################################################################
# CREATING THE NAMESPACE $UserNamespace thanks to $UserYAMLDir/$UserNSCreationFile bash script

$UserYAMLDir/$UserNSCreationFile


################################################################################################################
# SPECIFIC TO IBM MONTPELLIER: CREATING A SECRET TO PULL DOCKER IMAGE WITH FMOYEN ID
# (THIS TO OVERCOME GLOBAL LIMITATIONS)

if [ ! -z ${Montpellier+x} ]; then
  $UserYAMLDir/$MopSecretCreationFile
fi


################################################################################################################
# DISPLAYING THE USER YAML DEFINITION FILES AND STARTING THE POD

echo
echo "========================================================================================================================================="
echo "STARTING THE POD USING THESE DEFINITION YAML FILES FROM $UserYAMLDir DIRECTORY:"
echo "------------------------------------------------------------------------------------------------------------------------"
echo "  Binary Image PV creation :                 `basename $UserImagesDevice_PvYamlFile`"
echo "  Binary Image PVC creation :                `basename $UserImagesDevice_PvcYamlFile`"
echo
echo "  CAPIapp deployment creation:               `basename $UserYamlFile`"
echo "-----------------------------------------------------------------------------------------------------------------------------------------"

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

echo "========================================================================================================================================="
echo


################################################################################################################
# DISPLAYING NEWLY CREATED RESOURCES INFO

echo
echo "========================================================================================================================================="
echo "HERUNDER INFO ABOUT THE NEWLY CRATED RESOURCES:"
echo
echo "------------------------------------------------------------------------"
echo "oc describe namespace/$UserNamespace" 
oc describe namespace/$UserNamespace
echo
echo "------------------------------------------------------------------------"
echo "oc -n $UserNamespace get all" 
oc -n $UserNamespace get all 
echo
echo "------------------------------------------------------------------------"
echo "oc -n $UserNamespace get pv/images-$UserName pvc/images-$UserName-pvc" 
oc -n $UserNamespace get pv/images-$UserName pvc/images-$UserName-pvc 
echo "========================================================================================================================================="
echo


################################################################################################################
# DISPLAYING THE BASH SCRIPT GENERATED FOR DELETING THE USER RESOURCES

echo
echo "========================================================================================================================================="
echo "SCRIPT TO USE IN ORDER TO DELETE THE USER RESOURCES (PV, PVC, POD, NAMESPACE):"
echo "------------------------------------------------------------------------"
echo "  Bash script to delete the user resources:      $UserYAMLDir/$UserResourcesDeleteScript"
echo "========================================================================================================================================="
echo
