FROM quay.io/centos/centos:stream8

RUN dnf install -y langpacks-en glibc-all-langpacks && dnf clean all -y
RUN dnf upgrade -y && dnf clean all -y

RUN dnf install -y yum-utils && dnf clean all -y
RUN dnf install -y iputils iproute && dnf clean all -y
RUN dnf config-manager --set-enabled powertools
RUN dnf install -y libcxl-devel libocxl-devel && dnf clean all -y

RUN dnf groupinstall -y "Development Tools" && dnf clean all -y
RUN dnf install -y pciutils && dnf clean all -y

WORKDIR /opt
RUN git clone https://github.com/OpenCAPI/oc-accel.git

WORKDIR /opt/oc-accel
RUN git fetch
RUN git checkout mmio_partial_reconfig
RUN make software

COPY scripts/my_oc_find_card /usr/local/bin
COPY scripts/my_oc_maint /usr/local/bin
COPY scripts/my_oc_maint_verbose /usr/local/bin
COPY scripts/get_card_id /usr/local/bin

RUN ln -s /opt/oc-accel/software/tools/oc_action_reprogram /usr/bin/oc_action_reprogram

RUN mkdir /home/user
RUN chmod g+w /home/user
ENV HOME=/home/user
WORKDIR /home/user

LABEL name="CAPIApp" \
      release="57" \
      summary="Image provided for using OpenCAPI Card in a ppc64le container using Partial Reconfiguration (made from a CentOS Stream container based on the Red Hat Universal Base Image)." \
      url="https://hub.docker.com/repository/docker/fmoyen/capiapp/general"

COPY scripts/StayUp.bash /usr/local/bin
CMD /usr/local/bin/StayUp.bash
