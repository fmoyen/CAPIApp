FROM quay.io/centos/centos:latest

RUN yum install -y langpacks-en glibc-all-langpacks
RUN yum upgrade -y

RUN yum install -y yum-utils
RUN yum-config-manager --enable powertools
RUN yum install -y libcxl-devel libocxl-devel

RUN yum install -y git sudo
RUN yum groupinstall -y "Development Tools"

WORKDIR /opt
RUN git clone https://github.com/open-power/snap.git
RUN git clone https://github.com/OpenCAPI/oc-accel.git
RUN git clone https://github.com/OpenCAPI/oc-utils.git
ADD libocxl_for_containers.tar.gz .

WORKDIR /opt/snap
RUN make software

WORKDIR /opt/oc-accel
RUN make software

WORKDIR /opt/oc-utils
RUN make install

RUN groupadd -g 1000 fabrice
RUN useradd -ms /bin/bash fabrice -u 1000 -g fabrice
RUN echo "fabrice:fabpasswd" | chpasswd
RUN echo "fabrice        ALL=(ALL)       NOPASSWD: ALL" | EDITOR='tee' visudo -f /etc/sudoers.d/specialUsers

COPY scripts/my_oc_find_card /usr/local/bin
COPY scripts/my_oc_maint /usr/local/bin
COPY scripts/my_oc_maint_verbose /usr/local/bin
COPY scripts/my_snap_find_card /usr/local/bin
COPY scripts/my_snap_maint /usr/local/bin

COPY StayUp.bash /usr/local/bin
#USER fabrice
#WORKDIR /home/fabrice
CMD /usr/local/bin/StayUp.bash 

