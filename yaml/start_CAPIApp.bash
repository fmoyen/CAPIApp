#!/bin/bash

################################################################################################################
Node="hawk08"
TempFile="/tmp/start_CAPIapp.tmp"
Choice="nul"
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
echo
echo "List of CAPI/OpenCAPI cards seen by the Device Plugin on $Node:"
echo "----------------------------------------------------------------"
oc describe node $Node | sed -n '/Capacity:/,/Allocatable/p' | grep xilinx | tee $TempFile
trap "rm $TempFile" EXIT
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

################################################################################################################
# OPENCAPI CASE
if `echo $CardChoice | grep -q ocapi`; then
  CardType="Opencapi"
  YamlRootDir="OPENCAPI-device_requested-with_sys_devices_ocxl/$Node"
  ls $YamlRootDir > $TempFile

  while ! grep -q $SubDir $TempFile; do
    echo
    echo "Please choose the working subdirectory you want to work with:"
    echo "-------------------------------------------------------------"
    cat $TempFile
    echo -e "?: \c"
    read SubDir
  done

  YamlDir=$YamlRootDir/$SubDir

  YamlFile=`ls $YamlDir/OPENCAPI-*${Choice}*deploy.yaml 2>/dev/null`

  OCXL0_Devices_PvYamlFile=`ls $YamlDir/sys-devices-ocxl.0-*${Choice}*pv.yaml 2>/dev/null`
  OCXL0_Devices_PvcYamlFile=`ls $YamlDir/sys-devices-ocxl.0-*${Choice}*pvc.yaml 2>/dev/null`
  OCXL0_Bus_PvYamlFile=`ls $YamlDir/sys-bus-ocxl.0-*${Choice}*pv.yaml 2>/dev/null`
  OCXL0_Bus_PvcYamlFile=`ls $YamlDir/sys-bus-ocxl.0-*${Choice}*pvc.yaml 2>/dev/null`

  OCXL1_Devices_PvYamlFile=`ls $YamlDir/sys-devices-ocxl.1-*${Choice}*pv.yaml 2>/dev/null`
  OCXL1_Devices_PvcYamlFile=`ls $YamlDir/sys-devices-ocxl.1-*${Choice}*pvc.yaml 2>/dev/null`
  OCXL1_Bus_PvYamlFile=`ls $YamlDir/sys-bus-ocxl.1-*${Choice}*pv.yaml 2>/dev/null`
  OCXL1_Bus_PvcYamlFile=`ls $YamlDir/sys-bus-ocxl.1-*${Choice}*pvc.yaml 2>/dev/null`

  Lib_Modules_PvYamlFile=`ls $YamlDir/lib-modules-pv.yaml 2>/dev/null`
  Lib_Modules_PvcYamlFile=`ls $YamlDir/lib-modules-pvc.yaml 2>/dev/null`

  Devices_Pci_Ocxl_PvYamlFile=`ls $YamlDir/sys-devices-ocxl-*${Choice}*pv.yaml 2>/dev/null`
  Devices_Pci_Ocxl_PvcYamlFile=`ls $YamlDir/sys-devices-ocxl-*${Choice}*pvc.yaml 2>/dev/null`

  Devices_Pci_PvYamlFile=`ls $YamlDir/sys-devices-pci-*${Choice}*pv.yaml 2>/dev/null`
  Devices_Pci_PvcYamlFile=`ls $YamlDir/sys-devices-pci-*${Choice}*pvc.yaml 2>/dev/null`

  Slots_PhySlot_PvYamlFile=`ls $YamlDir/sys-bus-slots-*${Choice}*pv.yaml 2>/dev/null`
  Slots_PhySlot_PvcYamlFile=`ls $YamlDir/sys-bus-slots-*${Choice}*pvc.yaml 2>/dev/null`

  ImagesDevice_PvYamlFile=`ls $YamlDir/images-${Choice}-pv.yaml 2>/dev/null`
  ImagesDevice_PvcYamlFile=`ls $YamlDir/images-${Choice}-pvc.yaml 2>/dev/null`

################################################################################################################
# CAPI CASE
else
  CardType="Capi"
  YamlDir="CAPI-device-requested/$Node"
  YamlFile=`ls $YamlDir/CAPI-device*${Choice}*deploy.yaml 2>/dev/null`
fi

################################################################################################################
echo
echo "Type of card:"
echo "-------------"
echo " --> $CardType"

echo
echo "Starting the CAPIapp using these yaml files from $YamlDir directory:"
echo "------------------------------------------------------------------------------------------------------------------------"
echo "  ocxl.0 /sys/devices PV creation (if needed):       `basename $OCXL0_Devices_PvYamlFile 2>/dev/null`"
echo "  ocxl.0 /sys/devices PVC creation (if needed):      `basename $OCXL0_Devices_PvcYamlFile 2>/dev/null`"
echo "  ocxl.1 /sys/devices PV creation (if needed):       `basename $OCXL1_Devices_PvYamlFile 2>/dev/null`"
echo "  ocxl.1 /sys/devices PVC creation (if needed):      `basename $OCXL1_Devices_PvcYamlFile 2>/dev/null`"
echo "  ocxl.0 /sys/bus PV creation (if needed):           `basename $OCXL0_Bus_PvYamlFile 2>/dev/null`"
echo "  ocxl.0 /sys/bus PVC creation (if needed):          `basename $OCXL0_Bus_PvcYamlFile 2>/dev/null`"
echo "  ocxl.1 /sys/bus PV creation (if needed):           `basename $OCXL1_Bus_PvYamlFile 2>/dev/null`"
echo "  ocxl.1 /sys/bus PVC creation (if needed):          `basename $OCXL1_Bus_PvcYamlFile 2>/dev/null`"
echo "  /lib/modules PV creation (if needed):              `basename $Lib_Modules_PvYamlFile 2>/dev/null`"
echo "  /lib/modules PVC creation (if needed):             `basename $Lib_Modules_PvcYamlFile 2>/dev/null`"
echo "  /sys/devices/pci.../ocxl PV creation (if needed):  `basename $Devices_Pci_Ocxl_PvYamlFile 2>/dev/null`"
echo "  /sys/devices/pci.../ocxl PVC creation (if needed): `basename $Devices_Pci_Ocxl_PvcYamlFile 2>/dev/null`"
echo "  /sys/devices/pci PV creation (if needed):          `basename $Devices_Pci_PvYamlFile 2>/dev/null`"
echo "  /sys/devices/pci PVC creation (if needed):         `basename $Devices_Pci_PvcYamlFile 2>/dev/null`"
echo "  /sys/bus/slots PhySlot PV creation (if needed):    `basename $Slots_PhySlot_PvYamlFile 2>/dev/null`"
echo "  /sys/bus/slots PhySlot PVC creation (if needed):   `basename $Slots_PhySlot_PvcYamlFile 2>/dev/null`"
echo "  Binary Image PV creation (if needed):              `basename $ImagesDevice_PvYamlFile 2>/dev/null`"
echo "  Binary Image PVC creation (if needed):             `basename $ImagesDevice_PvcYamlFile 2>/dev/null`"
echo
echo "  CAPIapp deployment creation:                      `basename $YamlFile`"

echo
echo
echo "List of available CAPIapp yaml files for $Choice in $YamlDir directory :" 
echo "---------------------------------------------------------------------------------------------------------------------------"
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
for i in $OCXL0_Devices_PvYamlFile $OCXL0_Devices_PvcYamlFile $OCXL0_Bus_PvYamlFile $OCXL0_Bus_PvcYamlFile $OCXL1_Devices_PvYamlFile $OCXL1_Devices_PvcYamlFile $Devices_Pci_Ocxl_PvYamlFile $Devices_Pci_Ocxl_PvcYamlFile $Devices_Pci_PvYamlFile $Devices_Pci_PvcYamlFile $OCXL1_Bus_PvYamlFile $OCXL1_Bus_PvcYamlFile $Lib_Modules_PvYamlFile $Lib_Modules_PvcYamlFile $Slots_PhySlot_PvYamlFile $Slots_PhySlot_PvcYamlFile $ImagesDevice_PvYamlFile $ImagesDevice_PvcYamlFile $YamlFile; do
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
