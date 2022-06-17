#!/bin/bash

################################################################################################################
# Script used for generating the docker CAPIApp Image and push it to the docker hub
# Author: Fabrice MOYEN (IBM)


################################################################################################################
# VARIABLES

docker_repository="fmoyen/capiapp"
ScriptDir=`realpath $0`
ScriptDir=`dirname $ScriptDir`
NoCache=""


################################################################################################################
# FUNCTIONS

function usage
{
  echo
  echo "===================================================================================================="
  echo "`basename $0` Usage:"
  echo "-------------------------"
  echo
  echo "Bash script used for generating the docker CAPIApp image and push it to the docker hub"
  echo
  echo "  + The parameters below are optional"
  echo
  echo "  + -n :  uses the --no-cache docker build option, forcing docker to re-build everything"
  echo "          (by default the cache is used)"
  echo
  echo "  + -h : shows this usage info"
  echo
  echo "Example:"
  echo "--------"
  echo "`basename $0`"
  echo "`basename $0` -n"
  echo
  echo "===================================================================================================="
  echo "For generating the CAPPapp application, this script $0 will use following steps:"
  echo
  echo " - Run docker command docker build -t [docker-repository]:[docker-tag] . to create a docker image of the new capiapp"
  echo " - Run docker command docker tag -t [docker-repository]:[docker-tag] [docker-repository]:latest to create a docker image of the new capiapp with latest tag"
  echo " - Check the new generating daemonset docker image with command docker images"
  echo " - Push the new docker image to a public dockerhub repository"
  echo
  echo "This script will use the following dockerhub repository: $docker_repository"
  echo "===================================================================================================="
  echo
  exit 0
}


################################################################################################################
# CHECKING IF PARAMETERS ARE GIVEN

while getopts ":nh" option; do
  case $option in
    n)
      NoCache="--no-cache"
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
# MAIN

echo; echo "===================================================================================================="
echo "===================================================================================================="
echo "For generating the CAPPapp application, this script $0 will use following steps:"
echo
echo " - Run docker command docker build -t [docker-repository]:[docker-tag] . to create a docker image of the new capiapp"
echo " - Run docker command docker tag -t [docker-repository]:[docker-tag] [docker-repository]:latest to create a docker image of the new capiapp with latest tag"
echo " - Check the new generating daemonset docker image with command docker images"
echo " - Push the new docker image to a public dockerhub repository"
echo
echo "This script will use the following dockerhub repository: $docker_repository"
echo

echo; echo "========================================================"
echo "Checking local architecture"
LocalArchitecture=`lscpu | grep Architecture`
echo $LocalArchitecture

if echo $LocalArchitecture | grep ppc64le >/dev/null; then 
   echo "Running on Power platform... Continuing !"
else
   echo "Not Running on Power platform... Exiting !"; echo
   exit 2
fi

echo; echo "========================================================"
echo "Getting the tag level"
echo;echo "Locally known images:"
docker images | grep $docker_repository

echo; echo -e "Which tag do you want to create ?: \c"
read docker_tag
if [[ -z $docker_tag ]]; then
   echo "You didn't provide any tag. Exiting..."; echo
   exit 1
fi

echo; echo "========================================================"
echo "Generating the docker image ${docker_repository}:$docker_tag"
cd $ScriptDir
docker build $NoCache -t ${docker_repository}:$docker_tag .

echo; echo "========================================================"
echo "Tagging with \"latest\" the new docker image"
docker tag ${docker_repository}:$docker_tag ${docker_repository}:latest

echo; echo "========================================================"
echo "Checking the docker image"
docker images | grep $docker_repository

echo; echo "========================================================"
echo "Pushing the docker image ${docker_repository}:$docker_tag to the docker hub"
docker push ${docker_repository}:$docker_tag

echo; echo "========================================================"
echo "Pushing the docker image ${docker_repository}:latest to the docker hub"
docker push ${docker_repository}:latest

echo; echo "========================================================"
echo "Bye !"
echo
