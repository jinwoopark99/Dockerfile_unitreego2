#!/bin/bash
# ============================================================================
# go2 컨테이너 시작 스크립트 (docker run)
#
# 사용:
#   ./docker-run.sh              # 컨테이너 시작
#                                #   없으면: 생성 + sudo 비밀번호 입력
#                                #   멈춰 있으면: start (비밀번호 유지)
#                                #   실행 중이면: 그대로
#   ./docker-run.sh --password   # sudo 비밀번호 변경
#   ./docker-run.sh --recreate   # 삭제 후 새로 생성 (새 이미지 pull 후 사용, 비밀번호 다시 입력)
#   ./docker-run.sh --stop       # 정지
#   ./docker-run.sh --rm         # 삭제
#
# 접속:
#   docker exec -it -u $USER go2 bash
#   (컨테이너 안 사용자 이름 / UID / HOME 이 host 사용자와 같음)
#
# sudo 비밀번호:
#   컨테이너를 만들 때 입력받아 컨테이너 안에만 설정 (이미지/host 파일에 저장하지 않음)
#   정지·재시작해도 유지, 컨테이너를 삭제하면 사라짐 → 다시 만들 때 새로 입력
#
# 환경변수로 변경 가능:
#   GO2_IMAGE      (기본: mirgaon/go2:humble-jetson)
#   GO2_CONTAINER  (기본: go2)
#   ROBOT_IF       (기본: enP8p1s0)  로봇 연결 network interface (기기마다 다를 수 있음)
#   ROS_DOMAIN_ID  (기본: 0)
# ============================================================================
set -euo pipefail

IMAGE="${GO2_IMAGE:-mirgaon/go2:humble-jetson}"
NAME="${GO2_CONTAINER:-go2}"
ROBOT_IF="${ROBOT_IF:-enP8p1s0}"
ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"
HOST_USER="$(id -un)"       # 컨테이너 안 사용자 이름을 host 와 같게
HOST_GROUP="$(id -gn)"
GO2_PW=""

info() { echo "== $*"; }
warn() { echo "WARNING: $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

container_exists()  { docker container inspect "${NAME}" > /dev/null 2>&1; }
container_running() { [ "$(docker container inspect -f '{{.State.Running}}' "${NAME}" 2>/dev/null)" = "true" ]; }

# 비밀번호 입력 → GO2_PW (메모리에만 보관)
ask_password() {
    echo "== Set sudo password for container user '${HOST_USER}' (use a different one from your host account)"
    local pw2
    read -r -s -p "New password: " GO2_PW; echo
    read -r -s -p "Retype new password: " pw2; echo
    [ -n "${GO2_PW}" ] || die "Password is empty"
    [ "${GO2_PW}" = "${pw2}" ] || die "Passwords do not match"
}

# 실행 중인 컨테이너에 비밀번호 적용 (stdin 으로 전달 → 명령줄/환경변수에 남지 않음)
#   대상: 컨테이너 안 UID 1000 계정 (entrypoint 가 host 사용자 이름으로 바꾼 계정)
#   컨테이너 시작 직후에는 entrypoint 의 usermod 가 /etc/passwd 를 잠깐 잠글 수 있어서 몇 번 재시도
apply_password() {
    local _
    for _ in 1 2 3 4 5; do
        # shellcheck disable=SC2016  # 아래 $ 변수는 컨테이너 안의 sh 가 해석
        if printf '%s\n' "${GO2_PW}" | docker exec -i -u root "${NAME}" sh -c \
            'IFS= read -r pw; u="$(getent passwd 1000 | cut -d: -f1)"; printf "%s:%s\n" "$u" "$pw" | chpasswd' \
            2>/dev/null; then
            GO2_PW=""
            info "sudo password set"
            return 0
        fi
        sleep 1
    done
    GO2_PW=""
    die "Failed to set password. Retry with: ./docker-run.sh --password"
}

print_enter() {
    echo
    echo "Enter:  docker exec -it -u ${HOST_USER} ${NAME} bash"
}

# --- 옵션 처리 ---------------------------------------------------------------
case "${1:-}" in
    --password)
        container_exists || die "Container '${NAME}' not found. Create it first: ./docker-run.sh"
        container_running || { info "Starting ${NAME}"; docker start "${NAME}" > /dev/null; }
        ask_password
        apply_password
        exit 0 ;;
    --stop)
        if container_exists; then docker stop "${NAME}" > /dev/null; info "${NAME} stopped"
        else info "Container '${NAME}' not found"; fi
        exit 0 ;;
    --rm)
        if container_exists; then docker rm -f "${NAME}" > /dev/null; info "${NAME} removed"
        else info "Container '${NAME}' not found"; fi
        exit 0 ;;
    --recreate)
        if container_exists; then
            info "Removing existing ${NAME}"
            docker rm -f "${NAME}" > /dev/null
        fi ;;
    "") ;;
    *)
        die "Unknown option: $1  (usage: ./docker-run.sh [--password|--recreate|--stop|--rm])" ;;
esac

# --- 이미 있는 컨테이너: 비밀번호는 그대로 유지 -----------------------------
if container_exists; then
    if container_running; then
        info "${NAME} is already running"
    else
        info "Restarting ${NAME}"
        docker start "${NAME}" > /dev/null
    fi
    print_enter
    exit 0
fi

# --- 사전 점검 ---------------------------------------------------------------
[ "$(id -u)" = "1000" ] || warn "Host UID is $(id -u), not 1000. File permissions in HOME may not match."

ip link show "${ROBOT_IF}" > /dev/null 2>&1 \
    || warn "Network interface '${ROBOT_IF}' not found. Check ROBOT_IF (ip -br link)."

docker image inspect "${IMAGE}" > /dev/null 2>&1 \
    || { info "Image ${IMAGE} not found locally. Pulling..."; docker pull "${IMAGE}"; }

# 컨테이너를 만들기 전에 비밀번호부터 입력 (잘못 입력하면 컨테이너 생성 없이 종료)
ask_password

# --- 선택 옵션 (있을 때만 추가) ---------------------------------------------
OPTS=()

# GPU (Jetson nvidia runtime)
if docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"'; then
    OPTS+=(--runtime nvidia)
else
    warn "nvidia runtime not found. Running without GPU."
fi

# Xbox controller / USB
[ -e /dev/input ]   && OPTS+=(--device /dev/input:/dev/input)
[ -e /dev/bus/usb ] && OPTS+=(--device /dev/bus/usb:/dev/bus/usb)

# jtop (jetson-stats 설치된 경우만 — 없을 때 mount 하면 빈 디렉토리가 생김)
[ -S /run/jtop.sock ] && OPTS+=(-v /run/jtop.sock:/run/jtop.sock)

# X11 GUI
[ -d /tmp/.X11-unix ] && OPTS+=(-v /tmp/.X11-unix:/tmp/.X11-unix:rw)

# --- 실행 --------------------------------------------------------------------
info "Creating ${NAME} (image: ${IMAGE}, ROBOT_IF: ${ROBOT_IF})"
docker run -dit \
    --name "${NAME}" \
    --hostname go2-dock \
    --add-host go2-dock:127.0.1.1 \
    --network host --ipc host --pid host \
    --cap-add SYS_NICE --ulimit rtprio=99 --ulimit memlock=-1 \
    -e ROBOT_IF="${ROBOT_IF}" \
    -e ROS_DOMAIN_ID="${ROS_DOMAIN_ID}" \
    -e DISPLAY="${DISPLAY:-}" \
    -e QT_X11_NO_MITSHM=1 \
    -e HOST_USER="${HOST_USER}" \
    -e HOST_GROUP="${HOST_GROUP}" \
    -e HOST_HOME="${HOME}" \
    -v "${HOME}:${HOME}" \
    -w "${HOME}" \
    "${OPTS[@]}" \
    "${IMAGE}" bash > /dev/null

apply_password

info "${NAME} is running"
print_enter
