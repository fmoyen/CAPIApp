#!/bin/bash

Node="hawk08"
TempFile="/tmp/start_CAPIapp.tmp"
Choice="nul"
OCXL0_DevicesPvYamlFile=""
OCXL0_DevicesPvcYamlFile=""
OCXL1_DevicesPvYamlFile=""
OCXL1_DevicesPvcYamlFile=""
OCXL0_BusPvYamlFile=""
OCXL0_BusPvcYamlFile=""
OCXL1_BusPvYamlFile=""
OCXL1_BusPvcYamlFile=""
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

  OCXL0_DevicesPvYamlFile=`ls $YamlDir/sys-devices-ocxl.0-*${Choice}*pv.yaml`
  OCXL0_DevicesPvcYamlFile=`ls $YamlDir/sys-devices-ocxl.0-*${Choice}*pvc.yaml`
  OCXL0_BusPvYamlFile=`ls $YamlDir/sys-bus-ocxl.0-*${Choice}*pv.yaml`
  OCXL0_BusPvcYamlFile=`ls $YamlDir/sys-bus-ocxl.0-*${Choice}*pvc.yaml`

  OCXL1_DevicesPvYamlFile=`ls $YamlDir/sys-devices-ocxl.1-*${Choice}*pv.yaml`
  OCXL1_DevicesPvcYamlFile=`ls $YamlDir/sys-devices-ocxl.1-*${Choice}*pvc.yaml`
  OCXL1_BusPvYamlFile=`ls $YamlDir/sys-bus-ocxl.1-*${Choice}*pv.yaml`
  OCXL1_BusPvcYamlFile=`ls $YamlDir/sys-bus-ocxl.1-*${Choice}*pvc.yaml`

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
echo "  ocxl.0 /sys/devices PV creation (if needed):      `basename $OCXL0_DevicesPvYamlFile 2>/dev/null`"
echo "  ocxl.0 /sys/devices PVC creation (if needed):     `basename $OCXL0_DevicesPvcYamlFile 2>/dev/null`"
echo "  ocxl.1 /sys/devices PV creation (if needed):      `basename $OCXL1_DevicesPvYamlFile 2>/dev/null`"
echo "  ocxl.1 /sys/devices PVC creation (if needed):     `basename $OCXL1_DevicesPvcYamlFile 2>/dev/null`"
echo "  ocxl.0 /sys/bus PV creation (if needed):          `basename $OCXL0_BusPvYamlFile 2>/dev/null`"
echo "  ocxl.0 /sys/bus PVC creation (if needed):         `basename $OCXL0_BusPvcYamlFile 2>/dev/null`"
echo "  ocxl.1 /sys/bus PV creation (if needed):          `basename $OCXL1_BusPvYamlFile 2>/dev/null`"
echo "  ocxl.1 /sys/bus PVC creation (if needed):         `basename $OCXL1_BusPvcYamlFile 2>/dev/null`"
echo "  Binary Image PV creation (if needed):             `basename $ImagesDevicePvYamlFile 2>/dev/null`"
echo "  Binary Image PVC creation (if needed):            `basename $ImagesDevicePvcYamlFile 2>/dev/null`"
echo
echo "  CAPIapp deployment creation:                      `basename $YamlFile`"

echo
echo
echo "List of available CAPIapp yaml files for $Choice in $YamlDir directory :" 
echo "---------------------------------------------------------------------------------------------------------------------"
basename -a `ls $YamlDir/*CAPI*$Choice*.yaml`
echo
echo "please give the alternative one that you may want, or leave empty if you want to use `basename $YamlFile`:"
echo -e "?: \c"
read YamlFileOther

if [ "$YamlFileOther" != "" ]; then
  YamlFile=$YamlDir/$YamlFileOther
else
  echo "--> `basename $YamlFile`"
fi

echo
echo "starting the CAPIapp:"
echo "---------------------"
for i in $OCXL0_DevicesPvYamlFile $OCXL0_DevicesPvcYamlFile $OCXL0_BusPvYamlFile $OCXL0_BusPvcYamlFile $OCXL1_DevicesPvYamlFile $OCXL1_DevicesPvcYamlFile $OCXL1_BusPvYamlFile $OCXL1_BusPvcYamlFile $ImagesDevicePvYamlFile $ImagesDevicePvcYamlFile $YamlFile; do
  echo 
  echo "oc create -f $i"
  oc create -f $i
  echo 
done

echo
