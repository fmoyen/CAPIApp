#!/bin/bash
##############################################################################################################
# Objective:
# A dummy rolling application which is just here to keep the container up
# Author:
# Fabrice MOYEN
##############################################################################################################

FABLOG=/tmp/stayup.log
FABTMP=/tmp/stayup.tmp
> $FABLOG

echo; echo "##############################################################################"
cat /etc/os-release | grep PRETTY
echo "------------------------------------------------------------------------------"
date
echo "------------------------------------------------------------------------------"
echo "Welcome to StayUp Application"
echo "(Just pushing date to $FABLOG in a log rotating way...)"
echo "##############################################################################"


while true; do
	Today=$(date)
	#echo $Today
	echo $Today >> $FABLOG
	if [ $(cat $FABLOG | wc -l) -gt 60 ]; then 
		tail -n +2 $FABLOG > $FABTMP
		mv $FABTMP $FABLOG
	fi
	sleep 60
done
