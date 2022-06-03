#!/bin/bash

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
UserName=""
TempFile="/tmp/user_CAPIapp.tmp"
UserYAMLRootDir=/tmp
UserResourcesDeleteScript="resourcesDelete.bash"
CardName="nul"
OCXL0_Devices_PvYamlFile=""
OCXL0_Devices_PvcYamlFile=""
OCXL1_Devices_PvYamlFile=""
OCXL1_Devices_PvcYamlFile=""
OCXL0_Bus_PvYamlFile=""
OCXL0_Bus_PvcYamlFile=""
OCXL1_Bus_PvYamlFile=""
OCXL1_Bus_PvcYamlFile=""
Lib_Modules_PvYamlFile=""
Lib_Modules_PvcYamlFile=""
Devices_Pci__Ocxl_PvYamlFile=""
Devices_Pci_Ocxl__PvcYamlFile=""
Devices_Pci_PvYamlFile=""
Devices_Pci_PvcYamlFile=""
ImagesDevice_PvYamlFile=""
ImagesDevice_PvcYamlFile=""
Slots_PhySlot_PvYamlFile=""
Slots_PhySlot_PvcYamlFile=""
OCYamlFile=""
YamlRootDir=""
SubDir="nul"
YamlDir=""
CardType=""

################################################################################################################
# ASKING FOR THE USER NAME

while [[ "$UserName" == "" ]]; do
  echo
  echo "What is your name ? (no special character) ? :"
  echo "----------------------------------------------"
  read UserName
done

################################################################################################################
# CHOOSING THE CARD

echo
echo "List of CAPI/OpenCAPI cards seen by the Device Plugin on $Node:"
echo "----------------------------------------------------------------"
oc describe node $Node | sed -n '/Capacity:/,/Allocatable/p' | grep xilinx | tee $TempFile
trap "rm -f $TempFile" EXIT

echo
echo "List of CAPI/OpenCAPI cards requests / limts on $Node:"
echo "-------------------------------------------------------"
echo "(0 means no card has been allocated yet)"
echo -e "\t\t\t\t requests\tlimits"
oc describe node $Node | sed -n '/Allocated resources:/,//p' | grep xilinx

while ! grep -q $CardName $TempFile; do
  echo
  echo "Please choose between the following card:"
  echo "-----------------------------------------"
  cat $TempFile | awk -F"-" '{print $2}' | awk -F"_" '{print $1}'
  echo -e "?: \c"
  read CardName
done

echo
CardFullName=`grep $CardName $TempFile | awk -F":" '{print $1}' | sed 's/ //g'`
echo "your card choice is: $CardFullName"

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
# CHOOSING THE POD YAML DEFINITION FILE

echo
echo "Type of card:"
echo "-------------"
echo " --> $CardType"

echo
echo "Starting the CAPIapp using these yaml files from $YamlDir directory:"
echo "------------------------------------------------------------------------------------------------------------------------"
echo "  Binary Image PV creation (if needed):              `basename $ImagesDevice_PvYamlFile 2>/dev/null`"
echo "  Binary Image PVC creation (if needed):             `basename $ImagesDevice_PvcYamlFile 2>/dev/null`"
echo
echo "  CAPIapp deployment creation:                      `basename $YamlFile`"

echo
echo
echo "List of available CAPIapp yaml files for $CardName in $YamlDir directory :" 
echo "---------------------------------------------------------------------------------------------------------------------------"
for i in `ls $YamlDir/*CAPI*.yaml`; do
   basename -a $i
done

echo
echo "please give the alternative one that you may want, or leave empty if you want to use `basename $YamlFile`:"
echo -e "?: \c"
read YamlFileOther

if [ "$YamlFileOther" != "" ]; then
  YamlFile=$YamlDir/$YamlFileOther
else
  echo "--> `basename $YamlFile`"
fi

################################################################################################################
# BUILDING THE YAML FILES (IMAGES+POD) WITH THE GIVEN INFO

UserYAMLDir="$UserYAMLRootDir/$UserName"
mkdir -p $UserYAMLDir
#trap "rm -f $TempFile; rm -rf $UserYAMLDir" EXIT

#---------------------------------------------------------------------------------------------------------------
# Replacing <USER> / <CARD> by $UserName / $CardName in the yaml definition files

echo
echo "Building the User/Card specific yaml definition files replacing:"
echo "----------------------------------------------------------------"
echo "  + <USER> --> $UserName"
echo "  + <CARD> --> $CardName"
echo "  + <CARD_REF> -->$CardFullName"

for file in $ImagesDevice_PvYamlFile $ImagesDevice_PvcYamlFile $YamlFile; do
  sed "s!<USER>!$UserName!g; s!<CARD>!$CardName!g; s!<CARD_REF>!$CardFullName!g" $file > $UserYAMLDir/`basename $file`
done

UserImagesDevice_PvYamlFile="$UserYAMLDir/`basename $ImagesDevice_PvYamlFile`"
UserImagesDevice_PvcYamlFile="$UserYAMLDir/`basename $ImagesDevice_PvcYamlFile`"
UserYamlFile="$UserYAMLDir/`basename $YamlFile`"

#---------------------------------------------------------------------------------------------------------------
# Building the script that will be responsible for deleting all user resources (PV, PVC, POD, etc)

cat <<EOF >> $UserYAMLDir/$UserResourcesDeleteScript
#!/bin/bash

# Script that will delete all resources for the user $UserName (PV, PVC, POD, etc)

# Deleting the Deployment (with the ReplicatSet and the Pod coming with it)
oc -n fabriceproject delete deployment.apps/oc-$UserName-$CardName

# Deleting PVC & PV
oc -n fabriceproject delete persistentvolumeclaim/images-$UserName-pvc
oc delete persistentvolume/images-$UserName
EOF

chmod u+x $UserYAMLDir/$UserResourcesDeleteScript

################################################################################################################
# STARTING THE POD

echo
echo "starting the CAPIapp:"
echo "---------------------"
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

  echo 
done

echo
