#!/bin/bash
# ============================================================================
# go2:humble 이미지 빌드
#   - host 계정의 USERNAME / UID / GID 를 그대로 전달
#   - host 비밀번호 hash(/etc/shadow)를 BuildKit secret으로 전달
#     → 이미지 layer/history 에 남지 않음, 컨테이너 안에서 host와 같은 비밀번호로 sudo
#
# 사용: ./build.sh [BASE_IMAGE]
#   예) ./build.sh                                   # 기본 l4t-jetpack:r36.4.0
#       ./build.sh nvcr.io/nvidia/l4t-jetpack:r36.4.3
#       ./build.sh ubuntu:22.04                      # GPU 불필요, 경량
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")"

BASE_IMAGE="${1:-nvcr.io/nvidia/l4t-jetpack:r36.4.0}"
IMAGE_TAG="go2:humble"

# host 비밀번호 hash 추출 (shadow 읽기에 sudo 필요)
PWHASH_FILE="$(mktemp)"
trap 'rm -f "${PWHASH_FILE}"' EXIT
sudo getent shadow "${USER}" | cut -d: -f2 > "${PWHASH_FILE}"
chmod 600 "${PWHASH_FILE}"

echo "== Building ${IMAGE_TAG}"
echo "   base : ${BASE_IMAGE}"
echo "   user : ${USER} (uid=$(id -u), gid=$(id -g))"

DOCKER_BUILDKIT=1 docker build \
    --build-arg BASE_IMAGE="${BASE_IMAGE}" \
    --build-arg USERNAME="${USER}" \
    --build-arg USER_UID="$(id -u)" \
    --build-arg USER_GID="$(id -g)" \
    --secret id=pwhash,src="${PWHASH_FILE}" \
    -t "${IMAGE_TAG}" .

echo "== Done. Run with:  docker compose run --rm go2"
