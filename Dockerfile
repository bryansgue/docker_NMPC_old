ARG UBUNTU_VERSION=20.04
FROM ubuntu:${UBUNTU_VERSION}

ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash","-c"]

ENV HOSTNAME=uav

# ------------------------------------------------
# Base system
# ------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo \
    locales \
    tzdata \
    ca-certificates \
    build-essential \
    cmake \
    git \
    curl \
    wget \
    unzip \
    pkg-config \
    python3 \
    python3-pip \
    python3-dev \
    libeigen3-dev \
    libblas-dev \
    liblapack-dev \
    software-properties-common \
    gnupg2 \
    lsb-release \
    iputils-ping \
    net-tools \
    dnsutils \
    x11-apps \
    libgl1-mesa-glx \
    libglu1-mesa \
    libxkbcommon-x11-0 \
    libxcb-xinerama0 \
    cargo \
    rustc \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------
# Locales
# ------------------------------------------------
RUN locale-gen en_US en_US.UTF-8
ENV LANG=en_US.UTF-8

# ------------------------------------------------
# ROS1 NOETIC
# ------------------------------------------------
RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key | apt-key add -

RUN echo "deb http://packages.ros.org/ros/ubuntu $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/ros1.list

RUN apt-get update && apt-get install -y \
    ros-noetic-ros-base \
    ros-noetic-rviz \
    ros-noetic-cv-bridge \
    ros-noetic-image-transport \
    ros-noetic-vision-opencv \
    python3-opencv \
    python3-rosdep \
    python3-rosinstall \
    python3-wstool \
    && rm -rf /var/lib/apt/lists/*

RUN rosdep init || true

ENV ROS_DISTRO=noetic

# ------------------------------------------------
# Create user
# ------------------------------------------------
ARG USERNAME=uav
ARG USER_UID=1000
ARG USER_GID=1000

RUN groupadd --gid $USER_GID $USERNAME && \
    useradd -m -s /bin/bash --uid $USER_UID --gid $USER_GID $USERNAME && \
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER $USERNAME
WORKDIR /home/$USERNAME

RUN rosdep update

# ------------------------------------------------
# Python libs
# ------------------------------------------------
RUN pip3 install --upgrade pip setuptools wheel

RUN python3 -m pip install --upgrade pip setuptools wheel && \
    python3 -m pip install --no-cache-dir \
    packaging matplotlib \
    "numpy>=1.21" \
    scipy \
    importlib_resources \
    casadi \
    cython \
    rospkg \
    catkin_pkg \
    osqp

# ------------------------------------------------
# Copy CasADi + ACADOS
# ------------------------------------------------
COPY casadi /home/$USERNAME/casadi
COPY acados /home/$USERNAME/acados

USER root
RUN chown -R $USERNAME:$USERNAME /home/$USERNAME/casadi /home/$USERNAME/acados
USER $USERNAME

ENV ACADOS_SOURCE_DIR=/home/$USERNAME/acados
ENV LD_LIBRARY_PATH=/home/$USERNAME/acados/lib:/home/$USERNAME/casadi:$LD_LIBRARY_PATH
ENV PYTHONPATH=/home/$USERNAME:${PYTHONPATH}

# ------------------------------------------------
# Install ACADOS python interface
# ------------------------------------------------
RUN pip3 install -e /home/$USERNAME/acados/interfaces/acados_template

# ------------------------------------------------
# Install modern Rust/Cargo and build t_renderer
# compatible with Ubuntu 20.04 / ROS Noetic
# ------------------------------------------------
ENV PATH="/home/$USERNAME/.cargo/bin:${PATH}"

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal && \
    /home/$USERNAME/.cargo/bin/rustup default stable

RUN git clone --branch v0.2.0 --depth 1 https://github.com/acados/tera_renderer.git /home/$USERNAME/tera_renderer && \
    cd /home/$USERNAME/tera_renderer && \
    /home/$USERNAME/.cargo/bin/cargo build --verbose --release && \
    mkdir -p /home/$USERNAME/acados/bin && \
    cp target/release/t_renderer /home/$USERNAME/acados/bin/t_renderer && \
    chmod +x /home/$USERNAME/acados/bin/t_renderer

ENV PATH="/home/$USERNAME/acados/bin:/home/$USERNAME/.local/bin:/home/$USERNAME/.cargo/bin:${PATH}"
# ------------------------------------------------
# catkin workspace
# ------------------------------------------------
RUN mkdir -p /home/$USERNAME/catkin_ws/src

WORKDIR /home/$USERNAME/catkin_ws/src

#RUN git clone https://github.com/lfrecalde1/dual_quaternion.git

WORKDIR /home/$USERNAME/catkin_ws

RUN bash -c "source /opt/ros/noetic/setup.bash && catkin_make"

# ------------------------------------------------
# Workspace for host code
# ------------------------------------------------
WORKDIR /workspace

RUN echo "source /opt/ros/noetic/setup.bash" >> /home/$USERNAME/.bashrc
RUN echo "source /home/$USERNAME/catkin_ws/devel/setup.bash" >> /home/$USERNAME/.bashrc
RUN echo "export ROS_MASTER_URI=http://localhost:11311" >> /home/$USERNAME/.bashrc
RUN echo "export ROS_IP=127.0.0.1" >> /home/$USERNAME/.bashrc

CMD ["bash"]
