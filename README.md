# Unitree Go2 EDU — ROS2 Humble Docker (Jetson Orin Nano / JetPack 6)

Go2 EDU low-level 제어용 최소 Docker 환경.
이미지 내용: **ROS2 Humble (ros-base) + CycloneDDS 0.10.x / unitree_ros2 + unitree_sdk2 (C++)**, 그 외 `joy`, `rosbag2-mcap`, 빌드/디버그 도구.
자체 제어 코드(SRB MPC 등)는 이미지에 넣지 않고 `~/go2_ws`를 volume mount해서 개발한다.

컨테이너 사용자는 root가 아니라 **host 계정과 동일한 username / UID / GID / 비밀번호**로 생성된다
(비밀번호 hash는 BuildKit secret으로 전달되어 이미지 history에 남지 않음).

## Files

| File | 역할 |
|---|---|
| `Dockerfile` | 이미지 정의 (base → apt → user → unitree_ros2/sdk2 → entrypoint) |
| `build.sh` | host의 `$USER`, `id -u/-g`, `/etc/shadow` hash를 자동으로 넘겨 빌드 |
| `entrypoint.sh` | ROS2 / CycloneDDS / unitree_ros2 환경 source, `ROBOT_IF`로 `CYCLONEDDS_URI` 생성 |
| `docker-compose.yml` | 실행 옵션 (host network, /dev/input, RT priority, volume, X11) |

## Setup (Jetson)

```bash
# 0. host 점검
cat /etc/nv_tegra_release                     # r36.x.y 확인
docker info | grep -i nvidia                  # nvidia runtime 있는지
groups | grep docker || sudo usermod -aG docker $USER   # 이후 재로그인

# 1. clone
git clone https://github.com/jinwoopark99/Dockerfile_unitreego2 ~/go2_docker
cd ~/go2_docker && chmod +x build.sh entrypoint.sh
mkdir -p ~/go2_ws ~/go2_bags

# 2. build (30~60분, sudo 비밀번호 1회 입력)
./build.sh nvcr.io/nvidia/l4t-jetpack:r36.4.0    # r36 버전을 0단계 값에 맞출 것
#   GPU 불필요/경량:  ./build.sh ubuntu:22.04   (이 경우 compose의 runtime: nvidia 줄 삭제)

# 3. run
docker compose run --rm go2
```

## 컨테이너 안에서 확인

```bash
id && sudo -v                      # host와 같은 uid, host 비밀번호로 sudo
ros2 topic list                    # /lowstate, /sportmodestate
ros2 topic hz /lowstate            # ~500 Hz
```

## 자주 쓰는 것

```bash
ROBOT_IF=lo docker compose run --rm go2                       # sim (unitree_mujoco) 용
docker compose up -d go2 && docker compose exec go2 bash      # 상주 컨테이너
ros2 bag record -s mcap -o ~/go2_bags/<name> /lowstate /sportmodestate /joy
```

## Notes

- DDS는 `network_mode: host` 없으면 로봇 topic이 안 보인다.
- `ROBOT_IF` 기본값 `eth0`. Jetson dock의 로봇 쪽 interface 이름이 다르면 환경변수로 override.
- 빌드된 이미지에는 계정 비밀번호 hash가 포함되므로 Docker Hub에 올릴 경우 **private** repo로.
- `.sh` 실행 시 `bad interpreter: ^M` 에러가 나면 `sed -i 's/\r$//' *.sh`.
