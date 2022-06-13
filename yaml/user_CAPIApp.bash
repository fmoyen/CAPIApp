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
# We need to create a script to delete User PV, PVC, deployment and namespace


################################################################################################################
# VARIABLES

Verbose=0
UserName=""
TempFile="/tmp/user_CAPIapp.tmp"
UserYAMLRootDir=/tmp
UserResourcesDeleteScript="deleteUserResources.bash"
CardName="nul"
ImagesDevice_PvYamlFile=""
ImagesDevice_PvcYamlFile=""
UserNSCreationFile="createUserNamespace.bash"
MopSecretCreationFile="createMopDockerSecret.bash"
UserNamespace=""
YamlRootDir=""
SubDir="nul"
YamlDir=""
CardType=""
UserOption=0
CardOption=0
DockerPasswordOption=0
DockerPassword=""
RealPath=`realpath $0`

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
  echo "  + Missing parameters  => `basename $0` asks questions to get the missing parameters"
  echo
  echo "  + -u <User Name> : to give your user name"
  echo "  + -c <Card Name> : to give the card type you want"
  echo "  + -v             : verbose output"

  if [ ! -z ${Montpellier+x} ]; then
    echo
    echo "  + -p <Docker Personal Password> : Specific to IBM Montpellier (Docker fmoyen password to download Docker images)"
  fi

  echo
  echo "  + -h             : shows this usage info"
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

while getopts ":u:c:p:vh" option; do
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
# MONTPELLIER OR NOT ?

if [ ! -z ${Montpellier+x} ] && [ $Verbose -eq 1 ]; then
  echo
  echo "========================================================================================================================================="
  echo "MONTPELLIER CLUSTER"
  echo "========================================================================================================================================="
fi


################################################################################################################
# ASKING FOR THE USER NAME

if [ $UserOption -eq 0 ]; then
  echo
  echo "========================================================================================================================================="
  while [[ "$UserName" == "" ]]; do
    echo
    echo "What is your name ? (no special character) ? :"
    echo "----------------------------------------------"
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
# SPECIFIC TO IBM MONTPELLIER: ASKING FOR THE DOCKER fmoyen PASSWORD

if [ ! -z ${Montpellier+x} ]; then
  if [ $DockerPasswordOption -eq 0 ]; then
    echo
    echo "========================================================================================================================================="
    while [[ "$DockerPassword" == "" ]]; do
      echo
      echo "What is the Docker fmoyen Password ? :"
      echo "--------------------------------------"
      read DockerPassword
    done
    echo "========================================================================================================================================="

  else
    if [ $Verbose -eq 1 ]; then
      echo
      echo "========================================================================================================================================="
      echo "DOCKER PASSWORD HAS BEEN PROVIDED"
      echo "========================================================================================================================================="
    fi
  fi
fi


################################################################################################################
# CHOOSING THE CARD

TrapCmd="rm -f $TempFile"

echo
echo "========================================================================================================================================="
if [ -z ${Montpellier+x} ]; then    # NOT Montpellier so manually giving the list of available cards in the cluster
  echo "List of OpenCAPI cards allocatable:"
  echo "-----------------------------------"
  cat <<EOF | tee $TempFile
xilinx.com/fpga-ad9h3_ocapi-0x0667
xilinx.com/fpga-ad9h7_ocapi-0x0666
EOF
  trap "$TrapCmd" EXIT

else    # Montpellier, so directely getting the list of cards from the only IC922 worker node
  Node="hawk08"
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
  echo "(from `dirname $RealPath`/$YamlDir yaml files)"
echo "========================================================================================================================================="
fi

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
echo "---------------------------------"

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
echo "--------------------------------------------------------------------------------------------------------"

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
echo "========================================================================================================================================="

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

if [ $Verbose -eq 1 ]; then
  $UserYAMLDir/$UserNSCreationFile
else
  $UserYAMLDir/$UserNSCreationFile >/dev/null
fi


################################################################################################################
# SPECIFIC TO IBM MONTPELLIER: CREATING A SECRET TO PULL DOCKER IMAGE WITH FMOYEN ID
# (THIS TO OVERCOME GLOBAL LIMITATIONS)

if [ ! -z ${Montpellier+x} ]; then
  if [ $Verbose -eq 1 ]; then
    $UserYAMLDir/$MopSecretCreationFile
  else
    $UserYAMLDir/$MopSecretCreationFile >/dev/null
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
  echo "========================================================================================================================================="
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
echo "  $UserYAMLDir/$UserResourcesDeleteScript   --> Specific to $UserName user (This script will also remove $UserYAMLDir directory)"
echo "  `dirname $RealPath`/delete_UserResources.bash -u $UserName"
echo "========================================================================================================================================="

echo
