#!/bin/bash

Node="Hawk08"
TempFile="/tmp/start_CAPIapp.tmp"
Choice="nul"
PvYamlFile=""
PvcYamlFile=""
OCYamlFile=""

echo
echo "List of OpenCAPI cards seen by the Device Plugin on $Node:"
echo "-----------------------------------------------------------"
oc describe node hawk08 | sed -n '/Capacity:/,/Allocatable/p' | grep xilinx | grep ocapi | tee $TempFile
echo
echo "List of OpenCAPI cards requests / limts on $Node:"
echo "--------------------------------------------------"
oc describe node hawk08 | sed -n '/Allocated resources:/,//p' | grep xilinx | grep ocapi

while ! grep -q $Choice $TempFile; do
  echo
  echo "Please choose between the following card:"
  echo "-----------------------------------------"
  cat $TempFile | awk -F"-" '{print $2}' | awk -F"_" '{print $1}'
  echo -e "?: \c"
  read Choice
done

echo
echo "your card choice is: `grep $Choice $TempFile`"


OCYamlFile=`ls OPENCAPI*${Choice}*.yaml`
PvYamlFile=`ls sys*${Choice}*pv.yaml`
PvcYamlFile=`ls sys*${Choice}*pvc.yaml`

echo
echo "starting the CAPIapp using these yaml files:"
echo "--------------------------------------------"
echo "  PV creation (if needed): $PvYamlFile"
echo "  PVC creation (if needed): $PvcYamlFile"
echo "  CAPIapp deployment creation: $OCYamlFile"
echo

for i in $PvYamlFile $PvcYamlFile $OCYamlFile; do
  echo 
  echo "oc create -f $i"
  oc create -f $i
  echo 
done

echo
