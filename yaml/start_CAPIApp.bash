#!/bin/bash

Node="hawk08"
TempFile="/tmp/start_CAPIapp.tmp"
Choice="nul"
DevicesPvYamlFile=""
DevicesPvcYamlFile=""
BusPvYamlFile=""
BusPvcYamlFile=""
ImagesDevicePvYamlFile=""
ImagesDevicePvcYamlFile=""
OCYamlFile=""
YamlDir=""
CardType=""

echo
echo "List of CAPI/OpenCAPI cards seen by the Device Plugin on $Node:"
echo "----------------------------------------------------------------"
oc describe node $Node | sed -n '/Capacity:/,/Allocatable/p' | grep xilinx | tee $TempFile
echo
echo "List of CAPI/OpenCAPI cards requests / limts on $Node:"
echo "-------------------------------------------------------"
echo "(0 means no card has been allocated yet)"
echo -e "\t\t\t\t requests\tlimits"
oc describe node $Node | sed -n '/Allocated resources:/,//p' | grep xilinx

while ! grep -q $Choice $TempFile; do
  echo
  echo "Please choose between the following card:"
  echo "-----------------------------------------"
  cat $TempFile | awk -F"-" '{print $2}' | awk -F"_" '{print $1}'
  echo -e "?: \c"
  read Choice
done

echo
CardChoice=`grep $Choice $TempFile | awk -F":" '{print $1}'`
echo "your card choice is: $CardChoice"

if `echo $CardChoice | grep -q ocapi`; then
  CardType="Opencapi"
  YamlDir="OPENCAPI-device_requested-with_sys_devices_ocxl/$Node"
  YamlFile=`ls $YamlDir/OPENCAPI-device*${Choice}*deploy.yaml`
  DevicesPvYamlFile=`ls $YamlDir/sys-devices*${Choice}*pv.yaml`
  DevicesPvcYamlFile=`ls $YamlDir/sys-devices*${Choice}*pvc.yaml`
  BusPvYamlFile=`ls $YamlDir/sys-bus*${Choice}*pv.yaml`
  BusPvcYamlFile=`ls $YamlDir/sys-bus*${Choice}*pvc.yaml`
  ImagesDevicePvYamlFile=`ls $YamlDir/images-${Choice}-pv.yaml`
  ImagesDevicePvcYamlFile=`ls $YamlDir/images-${Choice}-pvc.yaml`
else
  CardType="Capi"
  YamlDir="CAPI-device-requested/$Node"
  YamlFile=`ls $YamlDir/CAPI-device*${Choice}*deploy.yaml`
fi

echo
echo "Type of card:"
echo "-------------"
echo " --> $CardType"

echo
echo "starting the CAPIapp using these yaml files from $YamlDir directory:"
echo "------------------------------------------------------------------------------------------------------------------"
echo "  /sys/devices PV creation (if needed):      `basename $DevicesPvYamlFile 2>/dev/null`"
echo "  /sys/devices PVC creation (if needed):     `basename $DevicesPvcYamlFile 2>/dev/null`"
echo "  /sys/bus PV creation (if needed):          `basename $BusPvYamlFile 2>/dev/null`"
echo "  /sys/bus PVC creation (if needed):         `basename $BusPvcYamlFile 2>/dev/null`"
echo "  Binary Image PV creation (if needed):      `basename $ImagesDevicePvYamlFile 2>/dev/null`"
echo "  Binary Image PVC creation (if needed):     `basename $ImagesDevicePvcYamlFile 2>/dev/null`"
echo
echo "  CAPIapp deployment creation:               `basename $YamlFile`"

echo
echo "Do you want to choose (for testing purpose) a specific CAPIapp yaml file other than the one indicated above [y|n]?:"
echo "-------------------------------------------------------------------------------------------------------------------"
read YamlFileChoice
if [ "$YamlFileChoice" == "y" ] || [ "$YamlFileChoice" == "Y" ] || [ "$YamlFileChoice" == "yes" ]; then
  YamlFileOther=""
  while [ -z "$YamlFileOther" ]; do
    echo
    echo "List of available CAPIapp yaml files for $Choice in $YamlDir directory :" 
    echo "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -" 
    basename -a `ls $YamlDir/*CAPI*$Choice*.yaml`
    echo
    echo -e "please give the one that you want: \c"
    read YamlFileOther
  done
  YamlFile=$YamlDir/$YamlFileOther
else
  echo "--> so the answer is NO"
fi

echo
echo "starting the CAPIapp:"
echo "---------------------"
for i in $DevicesPvYamlFile $DevicesPvcYamlFile $BusPvYamlFile $BusPvcYamlFile $ImagesDevicePvYamlFile $ImagesDevicePvcYamlFile $YamlFile; do
  echo 
  echo "oc create -f $i"
  oc create -f $i
  echo 
done

echo
