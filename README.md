# Unitree Go2 EDU — ROS2 Humble Docker (Jetson Orin Nano / JetPack 6)

Go2 EDU low-level 제어용 최소 Docker 환경. Docker Hub: `mirgaon/go2`
이미지 내용: **ROS2 Humble (ros-base) + CycloneDDS 0.10.x / unitree_ros2 + unitree_sdk2 (C++)**, 그 외 `joy`, `rosbag2-mcap`, 빌드/디버그 도구.
자체 제어 코드(SRB MPC 등)는 이미지에 넣지 않고 `~/go2_ws`를 volume mount해서 개발한다.

**배포용 이미지**: build 한 기기의 user 정보가 이미지에 들어가지 않는다.

- 컨테이너 user는 고정 `go2` (UID/GID **1000**). host 계정 UID가 1000이면 mount한 파일 권한이 그대로 맞는다.
- sudo 비밀번호는 이미지에 없고, **컨테이너 시작 시 host의 `~/.go2_password`로 설정**된다 (기기마다 다르게 설정 가능).
- 외부 git source(unitree_ros2, unitree_sdk2, cyclonedds 등)는 `versions.env`의 commit으로 고정.

## Files

| File | 역할 |
|---|---|
| `Dockerfile` | 이미지 정의 (base → apt → user go2 → unitree_ros2/sdk2 (/opt) → entrypoint) |
| `versions.env` | 외부 git source 고정 commit 목록 |
| `build.sh` | `versions.env`를 읽어 빌드 (`GO2_IMAGE`로 이미지 이름 변경 가능) |
| `entrypoint.sh` | (root) 비밀번호 설정 → go2 전환 → ROS2 / CycloneDDS / unitree_ros2 환경 source, `ROBOT_IF`로 `CYCLONEDDS_URI` 생성 |
| `docker-compose.yml` | 실행 옵션 (host network, /dev/input, RT priority, volume, X11, 비밀번호 secret) |
| `docs/portable-image-plan.md` | v1 → v2 수정 내역 |

## 사용 (pull 해서 쓰기)

```bash
# 0. host 점검
id -u                                         # 1000 인지 확인
cat /etc/nv_tegra_release                     # (Jetson) r36.x.y 확인
groups | grep docker || sudo usermod -aG docker $USER   # 이후 재로그인

# 1. 기기마다 1회 준비
git clone https://github.com/jinwoopark99/Dockerfile_unitreego2 ~/go2_docker
mkdir -p ~/go2_ws ~/go2_bags
printf '%s' '원하는비밀번호' > ~/.go2_password && chmod 600 ~/.go2_password
docker login                                  # Docker Hub repo가 private인 경우

# 2. 실행
cd ~/go2_docker
docker compose pull
docker compose run --rm go2
```

> `~/.go2_password`의 비밀번호는 컨테이너 안 `go2` 계정의 sudo 비밀번호로만 쓰인다. host 실제 계정 비밀번호와 다르게 설정할 것.

## 직접 빌드

```bash
./build.sh                                    # 기본 l4t-jetpack:r36.4.0 → mirgaon/go2:humble-jetson
./build.sh nvcr.io/nvidia/l4t-jetpack:r36.4.3 # r36 버전을 host 에 맞출 때
GO2_IMAGE=go2:test ./build.sh ubuntu:22.04    # GPU 불필요/경량 (compose의 runtime: nvidia 줄 삭제)
```

## 컨테이너 안에서 확인

```bash
id && sudo -v                      # uid=1000(go2), ~/.go2_password 비밀번호로 sudo
ros2 topic list                    # /lowstate, /sportmodestate
ros2 topic hz /lowstate            # ~500 Hz
```

## 자주 쓰는 것

```bash
ROBOT_IF=lo docker compose run --rm go2                            # sim (unitree_mujoco) 용
docker compose up -d go2 && docker compose exec -u go2 go2 bash    # 상주 컨테이너 (-u go2 필수)
ros2 bag record -s mcap -o ~/go2_bags/<n> /lowstate /sportmodestate /joy
```

## Notes

- DDS는 `network_mode: host` 없으면 로봇 topic이 안 보인다.
- `ROBOT_IF` 기본값 `eth0`. Jetson dock의 로봇 쪽 interface 이름이 다르면 환경변수로 override.
- 컨테이너는 root로 시작해서 비밀번호만 설정하고 바로 `go2`로 전환된다. 그래서 `docker compose exec`에는 `-u go2`를 붙인다 (안 붙이면 root shell).
- 버전을 올릴 때는 `versions.env`만 수정하고 다시 빌드.
