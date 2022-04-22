FROM quay.io/centos/centos:stream8

RUN dnf install -y langpacks-en glibc-all-langpacks
RUN dnf upgrade -y

RUN dnf install -y dnf-utils
RUN dnf config-manager --set-enabled powertools
RUN dnf install -y libcxl-devel libocxl-devel

RUN dnf install -y git sudo
RUN dnf groupinstall -y "Development Tools"
RUN dnf install -y pciutils

#RUN dnf install -y openssh-server
#RUN systemctl start sshd

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

