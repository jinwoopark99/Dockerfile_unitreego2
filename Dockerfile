# syntax=docker/dockerfile:1.4
# ============================================================================
# Unitree Go2 EDU low-level control image — ROS2 Humble (Ubuntu 22.04 / JetPack 6)
#
# 배포용 이미지 (어느 기기에서나 pull 해서 사용)
#   - 고정 user: go2 (UID/GID 1000), 비밀번호 없음 → 컨테이너 실행 시 설정 (entrypoint.sh)
#   - 설치물은 /opt 아래 (user / host 와 무관한 경로)
#   - 외부 git source 는 versions.env 의 commit 으로 고정
#
# Layer 순서 (위: 거의 안 바뀜 / 아래: 자주 바뀜)
#   1. base image (L4T / Ubuntu 22.04)
#   2. apt: ROS2 Humble + CycloneDDS rmw + Go2 제어에 필요한 최소 패키지
#   3. user go2 (UID/GID 1000)
#   4. unitree_ros2 (CycloneDDS 0.10.x) + unitree_sdk2 빌드  (/opt 아래, root)
#   5. entrypoint
#
# Build: ./build.sh [BASE_IMAGE]   (versions.env 를 읽어 --build-arg 로 전달)
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
#    rosdep init 은 괄호로 묶어서, apt 실패가 || true 에 묻히지 않도록 함
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
        # --- 컨테이너 시작 시 root → go2 전환용 ---
        gosu \
    && (rosdep init || true) \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# 3. User go2 (UID/GID 1000 고정)
#    - 비밀번호는 이미지에 넣지 않음 (계정 잠김 상태)
#    - 컨테이너 시작 시 entrypoint.sh 가 /run/secrets/go2_password 로 설정
#    - base image 에 따라 없는 group 이 있을 수 있어서 없으면 생성
# ---------------------------------------------------------------------------
RUN for g in dialout input plugdev video; do \
        getent group "$g" > /dev/null || groupadd -r "$g"; \
    done \
    && groupadd --gid 1000 go2 \
    && useradd --uid 1000 --gid 1000 -m -s /bin/bash go2 \
    && usermod -aG sudo,dialout,input,plugdev,video go2

# rosdep cache 는 ~/.ros 에 저장되므로 go2 로 실행
USER go2
RUN rosdep update
USER root

# ---------------------------------------------------------------------------
# 4. unitree_ros2 + CycloneDDS 0.10.x  →  /opt/unitree_ros2
#    - 모든 source 는 versions.env 의 commit 으로 고정
#    - 주의: cyclonedds 빌드 전에 ROS를 source하지 말 것 (unitree_ros2 README)
# ---------------------------------------------------------------------------
ARG UNITREE_ROS2_REF
ARG RMW_CYCLONEDDS_REF
ARG CYCLONEDDS_REF
RUN : "${UNITREE_ROS2_REF:?versions.env 값 필요 — ./build.sh 로 빌드할 것}" \
    && : "${RMW_CYCLONEDDS_REF:?versions.env 값 필요}" \
    && : "${CYCLONEDDS_REF:?versions.env 값 필요}" \
    && git clone https://github.com/unitreerobotics/unitree_ros2 /opt/unitree_ros2 \
    && git -C /opt/unitree_ros2 checkout "${UNITREE_ROS2_REF}" \
    && cd /opt/unitree_ros2/cyclonedds_ws/src \
    && git clone https://github.com/ros2/rmw_cyclonedds \
    && git -C rmw_cyclonedds checkout "${RMW_CYCLONEDDS_REF}" \
    && git clone https://github.com/eclipse-cyclonedds/cyclonedds \
    && git -C cyclonedds checkout "${CYCLONEDDS_REF}" \
    && cd .. \
    && colcon build --packages-select cyclonedds --parallel-workers 2 \
    && source /opt/ros/humble/setup.bash \
    && colcon build --parallel-workers 2 \
    && rm -rf build log

# ---------------------------------------------------------------------------
# 4b. unitree_sdk2 (C++) — mode 전환(MotionSwitcher/Sport), stand example 등
#     설치 위치: /opt/unitree_robot (SDK 기본 경로)
#     root 로 실행 (build 중에는 sudo 사용 불가)
# ---------------------------------------------------------------------------
ARG UNITREE_SDK2_REF
RUN : "${UNITREE_SDK2_REF:?versions.env 값 필요 — ./build.sh 로 빌드할 것}" \
    && git clone https://github.com/unitreerobotics/unitree_sdk2 /tmp/unitree_sdk2 \
    && git -C /tmp/unitree_sdk2 checkout "${UNITREE_SDK2_REF}" \
    && cmake -S /tmp/unitree_sdk2 -B /tmp/unitree_sdk2/build -DCMAKE_BUILD_TYPE=Release \
    && cmake --build /tmp/unitree_sdk2/build -j2 \
    && cmake --install /tmp/unitree_sdk2/build \
    && rm -rf /tmp/unitree_sdk2

# ---------------------------------------------------------------------------
# 5. Entrypoint / shell 환경
#    ROBOT_IF: 로봇과 연결된 network interface (실물: eth0 등, sim: lo)
#    USER 를 지정하지 않음 → root 로 시작, entrypoint 가 비밀번호 설정 후 go2 로 전환
# ---------------------------------------------------------------------------
ENV RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \
    ROBOT_IF=eth0 \
    ROS_DOMAIN_ID=0

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh
# bashrc
RUN echo 'source /usr/local/bin/entrypoint.sh --env-only' >> /etc/bash.bashrc

WORKDIR /home/go2
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
