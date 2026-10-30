#!/bin/bash
# ============================================================================
# Go2 container entrypoint
#   [root 구간] go2 의 HOME 을 host 계정 HOME(HOST_HOME)으로 변경 → gosu 로 go2 전환
#   [go2 구간]  ROS2 Humble, CycloneDDS(0.10.x), unitree_ros2 환경 source
#               CYCLONEDDS_URI 를 ROBOT_IF 환경변수로 생성 (실물: eth0 등 / sim: lo)
#               ~/go2_ws/install 이 있으면 자동 source
#
# 사용:
#   entrypoint.sh <cmd>               → (root면 HOME 설정 후 go2로 전환) 환경 설정 후 <cmd> 실행
#   source entrypoint.sh --env-only   → 현재 shell에 환경만 적용 (/etc/bash.bashrc 용)
#
# sudo 비밀번호:
#   이미지에도, host 파일에도 저장하지 않음
#   docker-run.sh 가 컨테이너 생성 직후 입력받아 docker exec 로 설정
#   (컨테이너 안 /etc/shadow 에만 존재 → 컨테이너를 삭제하면 함께 사라짐)
# ============================================================================

# --- [root 구간] 사용자 이름 / HOME 을 host 와 맞춘 뒤 해당 user 로 전환 ---
if [ "$(id -u)" = "0" ] && [ "$1" != "--env-only" ]; then
    # 이미지의 UID 1000 계정 (처음엔 go2, 이미 이름을 바꿨으면 바뀐 이름)
    CUSER="$(getent passwd 1000 | cut -d: -f1)"
    CGROUP="$(getent group 1000 | cut -d: -f1)"

    # 1) 이름을 host 사용자 이름으로 변경 (HOST_USER / HOST_GROUP)
    if [ -n "${HOST_USER:-}" ] && [ "${HOST_USER}" != "${CUSER}" ]; then
        if getent passwd "${HOST_USER}" > /dev/null; then
            echo "WARNING: '${HOST_USER}' already exists in the image. Keeping user name '${CUSER}'." >&2
        else
            usermod -l "${HOST_USER}" "${CUSER}"
            CUSER="${HOST_USER}"
        fi
    fi
    HOST_GROUP="${HOST_GROUP:-${HOST_USER:-}}"
    if [ -n "${HOST_GROUP}" ] && [ "${HOST_GROUP}" != "${CGROUP}" ] \
       && ! getent group "${HOST_GROUP}" > /dev/null; then
        groupmod -n "${HOST_GROUP}" "${CGROUP}"
    fi

    # 2) HOME 을 host 계정 HOME 으로 변경
    if [ -n "${HOST_HOME:-}" ] && [ -d "${HOST_HOME}" ] \
       && [ "$(getent passwd "${CUSER}" | cut -d: -f6)" != "${HOST_HOME}" ]; then
        usermod -d "${HOST_HOME}" "${CUSER}"
    fi

    exec gosu "${CUSER}" "$0" "$@"
fi

# --- [go2 구간] ROS2 ---
source /opt/ros/humble/setup.bash

# --- CycloneDDS 0.10.x + unitree msg (unitree_go / unitree_api / unitree_hg) ---
UNITREE_ROS2_DIR=/opt/unitree_ros2
[ -f "${UNITREE_ROS2_DIR}/cyclonedds_ws/install/setup.bash" ] && \
    source "${UNITREE_ROS2_DIR}/cyclonedds_ws/install/setup.bash"

export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp

# --- DDS network interface (unitree_ros2/setup.sh 와 동일한 내용을 env로 생성) ---
ROBOT_IF="${ROBOT_IF:-eth0}"
export CYCLONEDDS_URI="<CycloneDDS><Domain><General><Interfaces>
  <NetworkInterface name=\"${ROBOT_IF}\" priority=\"default\" multicast=\"default\" />
</Interfaces></General></Domain></CycloneDDS>"

# --- 내 workspace ---
[ -f "${HOME}/go2_ws/install/setup.bash" ] && source "${HOME}/go2_ws/install/setup.bash"

# --- env만 적용하고 끝 (/etc/bash.bashrc 에서 source 될 때) ---
if [ "$1" == "--env-only" ]; then
    return 0 2>/dev/null || exit 0
fi

exec "$@"
