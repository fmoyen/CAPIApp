# CAPIApp Objective:
Develop / test a way to use a CAPI adapter in an Openshift App environment.

## Way to execute
"CMD /usr/local/bin/StayUp.bash" in the Dockerfile so the container automatically runs StayUp.bash when starting
(this will make the container staying alive)

## For generating the docker hub CAPIapp images, run the following script: Build-capiapp.sh
The Build-capiapp.sh script is here to generate the capiapp (thanks to the Dockerfile) and push it into docker hub.

The script is now using the https://github.com/OpenCAPI/libocxl master branch as it is now compatible with containers thanks to following commit:
https://github.com/OpenCAPI/libocxl/commit/e9e32473cf85717482e9d0f63a3c7a26e266fbb9

In details, the script is
  - cloning libocxl master branch,
  - running make command to generates obj files,
  - generating a libocxl_for_containers.tar.gz file,
  - pushing it into the capiapp dir
  - running docker build command to generate capiapp docker images (given tag + latest) which include this newly compiled libocxl
  - pushing these new tags into docker hub

