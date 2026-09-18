# syntax=docker/dockerfile:1.4
# ============================================================================
# Unitree Go2 EDU low-level control image — ROS2 Humble (Ubuntu 22.04 / JetPack 6)
#
# Layer 순서 (위: 거의 안 바뀜 / 아래: 자주 바뀜)
#   1. base image (L4T / Ubuntu 22.04)
#   2. apt: ROS2 Humble + CycloneDDS rmw + Go2 제어에 필요한 최소 패키지
#   3. non-root user (host UID/GID/비밀번호와 동일)
#   4. unitree_ros2 (CycloneDDS 0.10.x) + unitree_sdk2 빌드  (사용자 home 아래)
#   5. entrypoint
#
# Build: ./build.sh   (BuildKit secret으로 host 비밀번호 hash 전달)
# ============================================================================

# ---------------------------------------------------------------------------
# 1. Base image
#   - 기본: JetPack 컨테이너 (CUDA 포함, 나중에 GPU 쓸 여지)
#   - 용량이 부담되고 GPU가 필요 없으면 --build-arg BASE_IMAGE=ubuntu:22.04
#   - r36.x 는 host `cat /etc/nv_tegra_release` 와 맞출 것
# ---------------------------------------------------------------------------
ARG BASE_IMAGE=nvcr.io/nvidia/l4t-jetpack:r36.4.0
FROM ${BASE_IMAGE}

ARG DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 TZ=Asia/Seoul
SHELL ["/bin/bash", "-c"]

# ---------------------------------------------------------------------------
# 2. apt — ROS2 Humble + Go2 필수 패키지
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        locales curl gnupg2 lsb-release ca-certificates software-properties-common \
    && locale-gen en_US.UTF-8 \
    && add-apt-repository universe \
    && curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
        -o /usr/share/keyrings/ros-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
        http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" \
        > /etc/apt/sources.list.d/ros2.list \
    && apt-get update && apt-get install -y --no-install-recommends \
        # --- ROS2 Humble core + build tools ---
        ros-humble-ros-base \
        ros-dev-tools \
        python3-colcon-common-extensions \
        python3-rosdep \
        # --- DDS: Unitree는 CycloneDDS 사용 ---
        ros-humble-rmw-cyclonedds-cpp \
        ros-humble-rosidl-generator-dds-idl \
        # --- Go2 low-level 제어에 필요한 것 ---
        ros-humble-joy \
        ros-humble-rosbag2-storage-mcap \
        libyaml-cpp-dev \
        libeigen3-dev \
        libboost-dev \
        # --- C++ / Python 기본 ---
        build-essential cmake git pkg-config \
        python3-pip python3-numpy \
        # --- 최소 dev/debug 도구 ---
        sudo vim tmux htop gdb \
        net-tools iputils-ping iproute2 \
        joystick evtest \
    && rosdep init || true \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# 3. Non-root user — host 계정과 UID/GID/비밀번호 일치
#    비밀번호 hash는 이미지 layer에 남지 않도록 BuildKit secret으로 전달
# ---------------------------------------------------------------------------
# 기본값은 fallback일 뿐 — build.sh 가 host의 $USER / id -u / id -g 를 자동으로 넘겨줌
ARG USERNAME=unitree
ARG USER_UID=1000
ARG USER_GID=1000

RUN groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash ${USERNAME} \
    && usermod -aG sudo,dialout,input,plugdev,video ${USERNAME}

# host의 /etc/shadow hash를 그대로 적용 → host와 같은 비밀번호로 sudo 가능
RUN --mount=type=secret,id=pwhash \
    if [ -s /run/secrets/pwhash ]; then \
        usermod -p "$(cat /run/secrets/pwhash)" ${USERNAME}; \
    else \
        echo "WARNING: no pwhash secret given — password not set (sudo will fail)"; \
    fi

USER ${USERNAME}
WORKDIR /home/${USERNAME}
RUN rosdep update

# ---------------------------------------------------------------------------
# 4. unitree_ros2 + CycloneDDS 0.10.x  (Humble 공식 절차)
#    주의: cyclonedds 빌드 전에 ROS를 source하지 말 것 (README 요구사항)
# ---------------------------------------------------------------------------
RUN git clone --depth 1 https://github.com/unitreerobotics/unitree_ros2 \
    && cd unitree_ros2/cyclonedds_ws/src \
    && git clone --depth 1 -b humble https://github.com/ros2/rmw_cyclonedds \
    && git clone --depth 1 -b releases/0.10.x https://github.com/eclipse-cyclonedds/cyclonedds \
    && cd .. \
    && colcon build --packages-select cyclonedds --parallel-workers 2 \
    && source /opt/ros/humble/setup.bash \
    && colcon build --parallel-workers 2

# ---------------------------------------------------------------------------
# 4b. unitree_sdk2 (C++) — mode 전환(MotionSwitcher/Sport), stand example 등
#     설치 위치: /opt/unitree_robot (SDK 기본 경로)
# ---------------------------------------------------------------------------
RUN git clone --depth 1 https://github.com/unitreerobotics/unitree_sdk2 \
    && mkdir -p unitree_sdk2/build && cd unitree_sdk2/build \
    && cmake .. -DCMAKE_BUILD_TYPE=Release \
    && make -j2 \
    && sudo make install

# ---------------------------------------------------------------------------
# 5. Entrypoint / shell 환경
#    ROBOT_IF: 로봇과 연결된 network interface (실물: eth0 등, sim: lo)
# ---------------------------------------------------------------------------
ENV RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \
    ROBOT_IF=eth0 \
    ROS_DOMAIN_ID=0

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh
# docker exec 로 들어온 shell에도 같은 환경이 잡히도록 .bashrc에서 env만 source
RUN echo 'source /usr/local/bin/entrypoint.sh --env-only' >> ~/.bashrc

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
