#!/bin/bash
##############################################################################################################
# Objective:
# The APP the container needs to run when started in order to:
#   - Reset the OpenCAPI card
#   - Keep the container up
# Author:
# Fabrice MOYEN
##############################################################################################################

##############################################################################################################
# VARIABLES

ToolsPath=/usr/local/bin

Card=`$ToolsPath/get_card_id`

MountDir=`cat /proc/mounts | grep nfs | grep Images | awk '{print $2}'`
LogDir=$MountDir/Logs
BaseImageDir=$MountDir/Base
PartialBinFile=`ls $BaseImageDir/*partial.bin | head -1`  # Taking the first one just in case we find more than one partial binary files (this should not happen)

ResetLog=$LogDir/Reset_OC_Card_`date +%F_%X_%Z`.log

StayUpLog=/tmp/stayup.log


##############################################################################################################
# FUNCTIONS

#-------------------------------------------------------------------------------------------------------------
# Reset_OC_Card Objective:
# A function responsible for reseting an OpenCAPI card
#-------------------------------------------------------------------------------------------------------------
function Reset_OC_Card
{

  mkdir -p $LogDir
  chmod 777 $LogDir 2>/dev/null

  (
  echo
  echo "#####################################################################################################################################"
  echo "RUNNING Reset_OC_Card FUNCTION"
  echo "(The tool responsible for reseting the card with a generic partial image)"
  date
  echo
  echo "====================================================================================================================================="
  echo "Reseting card position $Card with $PartialBinFile"
  echo
  echo "====================================================================================================================================="
  echo "Card status BEFORE RESET"
  echo "------------------------"
  echo "$ToolsPath/ocapi_maint -C $Card"
  $ToolsPath/ocapi_maint -C $Card

  echo
  echo "====================================================================================================================================="
  echo "Reseting"
  echo "--------"
  echo "$ToolsPath/oc_action_reprogram -f -C $Card -i $PartialBinFile"
  $ToolsPath/oc_action_reprogram -f -C $Card -i $PartialBinFile

  ResetRC=`echo $?`
  if [ $ResetRC -ne 0 ]; then
    echo
    echo "##############################################"
    echo "# Reset operation failed (RC=$ResetRC)... EXITING   #"
    echo "##############################################"
    exit $ResetRC
    echo
  else
    echo
    echo "###################################################"
    echo "# Reset operation success (RC=$ResetRC)... CONTINUING   #"
    echo "###################################################"
  fi

  echo
  echo "====================================================================================================================================="
  echo "Card status AFTER RESET"
  echo "-----------------------"
  echo "$ToolsPath/ocapi_maint -C $Card"
  $ToolsPath/ocapi_maint -C $Card

  echo
  ) | tee $ResetLog

  # we need to get back the $ResetRC (Reset Return Code) from the subshell by reading it from the $ResetLog file
  ResetRC=`grep "RC=" $ResetLog | awk -F "RC=" '{print $2}' | awk -F ")" '{print $1}'`
  if [ $ResetRC -ne 0 ]; then
    echo "Exiting..."
    exit $ResetRC
  fi

}


#-------------------------------------------------------------------------------------------------------------
# StayUp Objective:
# A dummy rolling function which is just here to keep the container up
#-------------------------------------------------------------------------------------------------------------
function StayUp
{

  StayUpTMP=/tmp/stayup.tmp
  > $StayUpLog

  echo
  echo "#####################################################################################################################################"
  echo "RUNNING StayUp FUNCTION"
  echo "(Just pushing the date to $StayUpLog in a log rotating way in order to keep the container up and running...)"
  date

  while true; do
    Today=$(date)
    echo $Today >> $StayUpLog
    if [ $(cat $StayUpLog | wc -l) -gt 60 ]; then
      tail -n +2 $StayUpLog > $StayUpTMP
      mv $StayUpTMP $StayUpLog
    fi
    sleep 60
  done
}


##############################################################################################################
# MAIN

echo
echo "#####################################################################################################################################"
echo "Run_The_APP: That's the APP the container starts when initiated"
echo "(If the APP stops, the container dies)"
date

Reset_OC_Card

# If Reseting the card finished successfuly, then running StayUp which never ends (so keeping the container up and running)
StayUp

