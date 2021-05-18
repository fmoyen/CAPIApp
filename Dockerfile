FROM quay.io/centos/centos:latest
RUN yum upgrade -y
RUN yum install -y langpacks-en glibc-all-langpacks
RUN yum install -y yum-utils
RUN yum-config-manager --enable powertools
RUN yum install -y libcxl-devel libocxl-devel
COPY StayUp.bash /usr/local/bin
CMD /usr/local/bin/StayUp.bash 
