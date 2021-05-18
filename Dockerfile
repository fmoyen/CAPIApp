FROM quay.io/centos/centos:latest
COPY StayUp.bash /usr/local/bin
CMD /usr/local/bin/StayUp.bash 
