#!/bin/bash
# ============================================================================
# Go2 이미지 빌드
#   - versions.env 의 고정 commit 을 --build-arg 로 전달
#   - host user / UID / 비밀번호는 더 이상 사용하지 않음 (배포용 이미지)
#     sudo 비밀번호는 컨테이너 실행 시 ~/.go2_password 로 설정됨
#
# 사용: ./build.sh [BASE_IMAGE]
#   예) ./build.sh                                   # 기본 l4t-jetpack:r36.4.0
#       ./build.sh nvcr.io/nvidia/l4t-jetpack:r36.4.3
#       ./build.sh ubuntu:22.04                      # GPU 불필요, 경량
#   이미지 이름 변경:  GO2_IMAGE=go2:test ./build.sh ubuntu:22.04
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")"

BASE_IMAGE="${1:-nvcr.io/nvidia/l4t-jetpack:r36.4.0}"
IMAGE_TAG="${GO2_IMAGE:-mirgaon/go2-humble:latest}"

[ -f ./versions.env ] || { echo "ERROR: versions.env 없음" >&2; exit 1; }
set -a; source ./versions.env; set +a

echo "== Building ${IMAGE_TAG}"
echo "   base         : ${BASE_IMAGE}"
echo "   unitree_ros2 : ${UNITREE_ROS2_REF}"
echo "   unitree_sdk2 : ${UNITREE_SDK2_REF}"

DOCKER_BUILDKIT=1 docker build \
    --build-arg BASE_IMAGE="${BASE_IMAGE}" \
    --build-arg UNITREE_ROS2_REF \
    --build-arg UNITREE_SDK2_REF \
    --build-arg RMW_CYCLONEDDS_REF \
    --build-arg CYCLONEDDS_REF \
    -t "${IMAGE_TAG}" .

echo "== Done. Run with:  docker compose run --rm go2"
