#!/bin/bash
# ============================================================================
# Go2 container entrypoint
#   - ROS2 Humble, CycloneDDS(0.10.x), unitree_ros2 환경 source
#   - CYCLONEDDS_URI 를 ROBOT_IF 환경변수로 생성 (실물: eth0 / sim: lo)
#   - ~/go2_ws/install 이 있으면 자동 source
#
# 사용:
#   entrypoint.sh <cmd>        → 환경 설정 후 <cmd> 실행 (docker run 기본)
#   source entrypoint.sh --env-only  → 현재 shell에 환경만 적용 (.bashrc용)
# ============================================================================

# --- ROS2 ---
source /opt/ros/humble/setup.bash

# --- CycloneDDS 0.10.x + unitree_ros2 ---
UNITREE_ROS2_DIR="${HOME}/unitree_ros2"
[ -f "${UNITREE_ROS2_DIR}/cyclonedds_ws/install/setup.bash" ] && \
    source "${UNITREE_ROS2_DIR}/cyclonedds_ws/install/setup.bash"
[ -f "${UNITREE_ROS2_DIR}/install/setup.bash" ] && \
    source "${UNITREE_ROS2_DIR}/install/setup.bash"

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
