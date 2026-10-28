#!/bin/bash
# ============================================================================
# Go2 container entrypoint
#   [root 구간] go2 sudo 비밀번호 설정 → gosu 로 go2 전환
#   [go2 구간]  ROS2 Humble, CycloneDDS(0.10.x), unitree_ros2 환경 source
#               CYCLONEDDS_URI 를 ROBOT_IF 환경변수로 생성 (실물: eth0 / sim: lo)
#               ~/go2_ws/install 이 있으면 자동 source
#
# 사용:
#   entrypoint.sh <cmd>               → (root면 비밀번호 설정 후 go2로 전환) 환경 설정 후 <cmd> 실행
#   source entrypoint.sh --env-only   → 현재 shell에 환경만 적용 (.bashrc용)
#
# 비밀번호 전달:
#   compose secret → /run/secrets/go2_password  (host: ~/.go2_password, chmod 600)
#   파일이 없고 터미널이 있으면 직접 입력받음 (docker run -it 용 fallback)
# ============================================================================

# --- [root 구간] 비밀번호 설정 후 go2 로 전환 ---
if [ "$(id -u)" = "0" ] && [ "$1" != "--env-only" ]; then
    if [ -s /run/secrets/go2_password ]; then
        echo "go2:$(cat /run/secrets/go2_password)" | chpasswd
    elif [ -t 0 ]; then
        echo "go2 sudo 비밀번호 설정 (~/.go2_password 가 없어서 직접 입력):"
        passwd go2 || echo "WARNING: 비밀번호 설정 실패 — sudo 불가" >&2
    else
        echo "WARNING: 비밀번호 미설정 — sudo 불가 (host 에 ~/.go2_password 를 만들 것)" >&2
    fi
    exec gosu go2 "$0" "$@"
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

# --- 내 workspace (volume mount) ---
[ -f "${HOME}/go2_ws/install/setup.bash" ] && source "${HOME}/go2_ws/install/setup.bash"

# --- env만 적용하고 끝 (.bashrc 에서 source 될 때) ---
if [ "$1" == "--env-only" ]; then
    return 0 2>/dev/null || exit 0
fi

exec "$@"
