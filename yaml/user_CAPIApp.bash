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

Node="hawk08"
Menu=1
UserName=""
TempFile="/tmp/user_CAPIapp.tmp"
UserYAMLRootDir=/tmp
UserResourcesDeleteScript="resourcesDelete.bash"
CardName="nul"
ImagesDevice_PvYamlFile=""
ImagesDevice_PvcYamlFile=""
YamlRootDir=""
SubDir="nul"
YamlDir=""
CardType=""

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
  echo "  + No parameters given => `basename $0` starts the menu"
  echo "  + One parameter given when starting `basename $0` (parameter chosen among the menu possible options) => no menu or question, just doing what has been requested"
  echo "  + special case: when prune action is chosen as 1st parameter, you may provide nothing as 2nd parameter, or 'all', or any filesystem known by the tool (again see the menu options)"
  echo
  echo "  + -h / -? / --help: shows this usage info"
  echo
  echo "Example:"
  echo "--------"
  echo "`basename $0`"
  echo "`basename $0` all"
  echo "`basename $0` list"
  echo "`basename $0` prune"
  echo "`basename $0` prune all"
  echo "`basename $0` prune root"
  echo
  exit 0
}

################################################################################################################
# CHECKING IF PARAMETERS ARE GIVEN OR WE NEED TO ASK QUESTIONS
#

if [ $# -gt 0 ]; then
  Menu=0

  while getopts ":u:c:" option; do
    case $option in
      u)
        UserName=$OPTARG
      ;;
      c)
        CardName=$OPTARG
      ;;
      h)
        usage
      ;;

      \?) echo "Unknown option: -$OPTARG" >&2; exit 1;;
      :) echo "Missing option argument for -$OPTARG" >&2; exit 1;;
      *) echo "Unimplemented option: -$OPTARG" >&2; exit 1;;
    esac
  done
fi

################################################################################################################
# ASKING FOR THE USER NAME

if [ $Menu -eq 1 ]; then
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

################################################################################################################
# CHOOSING THE CARD

TrapCmd="rm -f $TempFile"

echo
echo "List of CAPI/OpenCAPI cards seen by the Device Plugin on $Node:"
echo "----------------------------------------------------------------"
oc describe node $Node | sed -n '/Capacity:/,/Allocatable/p' | grep xilinx | tee $TempFile
trap "$TrapCmd" EXIT

echo
echo "List of CAPI/OpenCAPI cards requests / limts on $Node:"
echo "-------------------------------------------------------"
echo "(0 means no card has been allocated yet)"
echo -e "\t\t\t\t requests\tlimits"
oc describe node $Node | sed -n '/Allocated resources:/,//p' | grep xilinx

if [ $Menu -eq 1 ]; then
  while ! grep -q $CardName $TempFile; do
    echo
    echo "Please choose between the following card:"
    echo "-----------------------------------------"
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

  CardType="Capi"
  YamlDir="CAPI-device-requested/$Node"
  YamlFile=`ls $YamlDir/CAPI-device*${CardName}*deploy.yaml 2>/dev/null | head -1`
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

#---------------------------------------------------------------------------------------------------------------
# Replacing <USER> / <CARD> by $UserName / $CardName in the yaml definition files

echo
echo "Building the User/Card specific yaml definition files replacing:"
echo "----------------------------------------------------------------"
echo "  + <USER> --> $UserName"
echo "  + <CARD> --> $CardName"
echo "  + <CARD_REF> -->$CardFullName"
echo
echo "(from $YamlDir yaml files)"

for file in $ImagesDevice_PvYamlFile $ImagesDevice_PvcYamlFile $YamlFile; do
  sed "s!<USER>!$UserName!g; s!<CARD>!$CardName!g; s!<CARD_REF>!$CardFullName!g" $file > $UserYAMLDir/`basename $file`
done

UserImagesDevice_PvYamlFile="$UserYAMLDir/`basename $ImagesDevice_PvYamlFile`"
UserImagesDevice_PvcYamlFile="$UserYAMLDir/`basename $ImagesDevice_PvcYamlFile`"
UserYamlFile="$UserYAMLDir/`basename $YamlFile`"

#---------------------------------------------------------------------------------------------------------------
# Building the script that will be responsible for deleting all user resources (PV, PVC, POD, etc)

cat <<EOF > $UserYAMLDir/$UserResourcesDeleteScript
#!/bin/bash

# Script that will delete all resources for the user $UserName (PV, PVC, POD, etc)

echo
echo "========================================================================================================================================="
echo "DELETING RESOURCES FOR USER $UserName..."
echo
echo "Warning: PVC deletion may take a minute as it needs to wait for Pod complete deletion"
echo "-----------------------------------------------------------------------------------------------------------------------------------------"

# Deleting the Deployment (with the ReplicatSet and the Pod coming with it)
echo
echo "oc -n fabriceproject delete deployment.apps/oc-$UserName-$CardName"
oc -n fabriceproject delete deployment.apps/oc-$UserName-$CardName

# Deleting PVC & PV
echo
echo "oc -n fabriceproject delete persistentvolumeclaim/images-$UserName-pvc"
oc -n fabriceproject delete persistentvolumeclaim/images-$UserName-pvc

echo
echo "oc delete persistentvolume/images-$UserName"
oc delete persistentvolume/images-$UserName

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
# DISPLAYING THE BASH SCRIPT GENERATED FOR DELETING THE USER RESOURCES

echo
echo "========================================================================================================================================="
echo "SCRIPT TO USE IN ORDER TO DELETE THE USER RESOURCES (PV, PVC, POD, etc):"
echo "------------------------------------------------------------------------"
echo "  Bash script to delete the user resources:      $UserYAMLDir/$UserResourcesDeleteScript"
echo "========================================================================================================================================="
echo
