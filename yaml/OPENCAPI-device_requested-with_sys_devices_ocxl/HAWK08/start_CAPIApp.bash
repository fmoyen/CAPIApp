#!/bin/bash

Node="Hawk08"
TempFile="/tmp/start_CAPIapp.tmp"
Choice="nul"

echo
echo "List of OpenCAPI cards available on $Node:"
echo "------------------------------------------"
oc describe node hawk08 | sed -n '/Capacity:/,/Allocatable/p' | grep xilinx | grep ocapi | tee $TempFile

while ! grep -q $Choice $TempFile; do
  echo
  echo "Please choose between the following card:"
  echo "-----------------------------------------"
  cat $TempFile | awk -F"-" '{print $2}' | awk -F"_" '{print $1}'
  echo -e "?: \c"
  read Choice
done

echo
echo "your choice is: `grep $Choice $TempFile`"

echo
echo "starting the CAPIapp using these yaml files:"
ls -la *${Choice}*

