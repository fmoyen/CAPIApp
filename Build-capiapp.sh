#!/bin/bash

docker_repository="fmoyen/capiapp"
libocxl_github="git@github.com:OPENCAPI/libocxl.git"
libocxl_tar_name="libocxl_for_containers.tar.gz"
ScriptDir=`realpath $0`
ScriptDir=`dirname $ScriptDir`

echo; echo "===================================================================================================="
echo "===================================================================================================="
echo "For generating the CAPPapp application, this script $0 will use following steps:"
echo
echo " - Run the git clone $libocxl_github command into /tmp to clone the master branch"
echo " - from /tmp/libocxl directory, run the make command using the Makefile"
echo " - from /tmp/libocxl directory, generate the $libocxl_tar_name file and push it into $ScriptDir"
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
echo "cloning the libocxl github master branch into /tmp"
echo "(cd /tmp; git clone $libocxl_github)"
rm -rf /tmp/libocxl
cd /tmp
git clone $libocxl_github

echo; echo "========================================================"
echo "Compiling the libocxl library"
echo "(cd /tmp/libocxl; make)"
cd /tmp/libocxl
make
echo
ls -la obj

echo; echo "========================================================"
echo "Generate the $libocxl_tar_name file and push it into $ScriptDir"
cd /tmp
tar cvzf $libocxl_tar_name libocxl
if [ $? -ne 0 ]; then
   echo "$libocxl_tar_name ganaration has failed ! Stopping here..."
   echo
   exit 1
fi  

rm -f $ScriptDir/$libocxl_tar_name
mv $libocxl_tar_name $ScriptDir
rm -rf /tmp/libocxl

echo; echo "========================================================"
echo "Generating the docker image ${docker_repository}:$docker_tag"
cd $ScriptDir
docker build -t ${docker_repository}:$docker_tag .

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
