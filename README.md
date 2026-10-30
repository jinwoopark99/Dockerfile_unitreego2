# Unitree Go2 EDU — ROS2 Humble Docker (Jetson / JetPack 6)

Go2 EDU low-level 제어용 Docker 환경. Docker Hub: `mirgaon/go2-humble:latest`

- 이미지 내용: **ROS2 Humble (ros-base) + CycloneDDS 0.10.x / unitree_ros2 + unitree_sdk2 (C++)**, 그 외 `joy`, `rosbag2-mcap`, 빌드/디버그 도구
- 대상: Go2 EDU Jetson (arm64, JetPack 6 / L4T r36)
- 자체 제어 코드는 이미지에 넣지 않음. 실행 시 **host HOME을 컨테이너의 같은 경로로 mount**해서 host 파일을 그대로 사용

**배포용 이미지**: build한 기기의 user, UID, 비밀번호 등 host 정보가 이미지에 들어가지 않음.

- 컨테이너 user: **host 사용자와 같은 이름 / UID / HOME** (예: `unitree`, 1000, `/home/unitree`)
  - 이미지에는 UID 1000 계정 `go2`로 들어 있고, 컨테이너 시작 시 host 사용자 이름으로 바뀜
  - host 계정 UID가 1000이어야 HOME 파일 권한이 맞음
- HOME / 작업 경로: host와 같은 경로 (예: `/home/unitree`)
- sudo 비밀번호: 이미지에도 host 파일에도 저장하지 않음. **컨테이너를 만들 때 입력**
- 외부 git source(unitree_ros2, unitree_sdk2, cyclonedds 등)는 `versions.env`의 commit으로 고정

## Quick start

```bash
# 0. 확인
id -u                                    # 1000
ip -br link                              # 로봇 연결 interface 이름 확인 (기본값: enP8p1s0)

# 1. repo 받기
git clone https://github.com/jinwoopark99/Dockerfile_unitreego2 ~/go2_docker
cd ~/go2_docker

# 2. 컨테이너 생성 (이미지가 없으면 자동 pull, sudo 비밀번호 입력)
./docker-run.sh                          # interface 가 다르면: ROBOT_IF=eth0 ./docker-run.sh

# 3. 접속
docker exec -it -u $USER go2 bash
```

컨테이너 안에서:
```bash
ros2 topic hz /lowstate                  # ~500 Hz
```

자세한 사용법: [`docs/container-usage.md`](docs/container-usage.md)

## Files

| File | 역할 |
|---|---|
| `Dockerfile` | 이미지 정의 (base → apt → user go2 → unitree_ros2/sdk2 (/opt) → entrypoint) |
| `versions.env` | 외부 git source 고정 commit |
| `build.sh` | `versions.env`를 읽어 이미지 build |
| `entrypoint.sh` | (root) 사용자 이름·HOME을 host와 맞춤 → 해당 user로 전환 → ROS2 / CycloneDDS / unitree 환경 설정 |
| `docker-run.sh` | **컨테이너 생성/시작/정지/삭제, sudo 비밀번호 설정** |
| `docker-compose.yml` | compose 실행 설정 (보조용, 아래 Notes 참고) |
| `docs/container-usage.md` | 컨테이너 사용법 |
| `docs/image-architecture.md` | 이미지 구성 상세 |
| `docs/portable-image-plan.md` | v1 → v2 수정 내역 |

## docker-run.sh

| 명령 | 동작 |
|---|---|
| `./docker-run.sh` | 없으면 생성(+비밀번호 입력), 멈춰 있으면 start, 실행 중이면 그대로 |
| `./docker-run.sh --password` | sudo 비밀번호 변경 |
| `./docker-run.sh --recreate` | 삭제 후 새로 생성 (새 이미지 pull 후, 비밀번호 다시 입력) |
| `./docker-run.sh --stop` / `--rm` | 정지 / 삭제 |

## 직접 build

```bash
./build.sh                                     # 기본 l4t-jetpack:r36.4.0 → mirgaon/go2-humble:latest
./build.sh nvcr.io/nvidia/l4t-jetpack:r36.4.3  # host L4T 버전에 맞출 때 (cat /etc/nv_tegra_release)
GO2_IMAGE=go2:test ./build.sh ubuntu:22.04     # GPU 불필요/경량
```

build는 오래 걸리므로 SSH 접속 중이라면 `tmux` 안에서 실행할 것.

## Notes

- DDS는 host network가 필요함. `docker-run.sh`가 `--network host`로 실행함.
- `ROBOT_IF`(로봇 연결 interface) 기본값은 `enP8p1s0`. 기기마다 다를 수 있으므로 `ip -br link`로 확인하고 다르면 `ROBOT_IF=<이름> ./docker-run.sh`.
- 접속할 때 `-u $USER`를 빠뜨리면 root shell로 들어감. alias 추천: `alias go2='docker exec -it -u $USER go2 bash'`
- 명령 하나만 실행할 때는 `bash -ic`: `docker exec -it -u $USER go2 bash -ic 'ros2 topic list'`
- host `~/.bashrc`도 컨테이너 shell에서 실행됨 (HOME mount). host 전용 ROS 설정이 있다면 `if [ ! -f /.dockerenv ]; then ... fi`로 감쌀 것.
- 이미지에 있던 rosdep cache는 HOME mount로 가려짐. 컨테이너에서 rosdep을 쓸 때는 처음 한 번 `rosdep update`.
- `docker-compose.yml`로 실행하는 경우 sudo 비밀번호가 설정되지 않음 → `docker exec -it go2 passwd go2`로 직접 설정. 기본은 `docker-run.sh` 사용.
- 컨테이너 hostname은 `go2-dock` (host와 구분하기 위함. 사용자 이름이 host와 같아서 프롬프트로 구분: `unitree@go2-dock`).
- GUI 앱(rviz2 등)이 `Authorization required` / `cannot open display`로 실패하면 host에서 `xhost +si:localuser:$USER` (X11 cookie가 host hostname 기준이라서).
- 버전을 올릴 때는 `versions.env`만 수정하고 다시 build.
