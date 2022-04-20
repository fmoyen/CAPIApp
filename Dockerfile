FROM quay.io/centos/centos:latest

RUN yum install -y langpacks-en glibc-all-langpacks
RUN yum upgrade -y

RUN yum install -y yum-utils
RUN yum-config-manager --enable powertools
RUN yum install -y libcxl-devel libocxl-devel

RUN yum install -y git sudo
RUN yum groupinstall -y "Development Tools"
RUN yum install -y pciutils

WORKDIR /opt
RUN git clone https://github.com/open-power/snap.git
RUN git clone https://github.com/OpenCAPI/oc-accel.git
RUN git clone https://github.com/OpenCAPI/oc-utils.git
ADD libocxl_for_containers.tar.gz .

WORKDIR /opt/snap
RUN make software

WORKDIR /opt/oc-accel
RUN git fetch
RUN git checkout mmio_partial_reconfig
RUN make software

WORKDIR /opt/oc-utils
RUN git fetch
RUN git checkout container
RUN make install

COPY scripts/my_oc_find_card /usr/local/bin
COPY scripts/my_oc_maint /usr/local/bin
COPY scripts/my_oc_maint_verbose /usr/local/bin
COPY scripts/my_snap_find_card /usr/local/bin
COPY scripts/my_snap_maint /usr/local/bin

RUN ln -s /opt/oc-accel/software/tools/oc_action_reprogram /usr/bin/oc_action_reprogram

COPY StayUp.bash /usr/local/bin
CMD /usr/local/bin/StayUp.bash 

