# go2 컨테이너 사용법 (`docker-run.sh` + `docker exec`)

`docker-run.sh`로 컨테이너를 **한 번 띄워두고**, 접속은 `docker exec`로 하는 방식.

| 항목 | 값 |
|---|---|
| 이미지 | `mirgaon/go2-humble:latest` |
| 컨테이너 이름 | `go2` |
| 시작 | `./docker-run.sh` |
| 접속 | `docker exec -it -u $USER go2 bash` |
| 컨테이너 user | **host 사용자와 같은 이름 / UID** (예: `unitree`, 1000) |
| HOME / 작업 경로 | host와 같은 경로 (예: `/home/unitree`) |
| 로봇 interface (`ROBOT_IF`) | 기본 `enP8p1s0` |

---

## 0. 사전 준비 (기기마다 1회)

```bash
id -u                                   # 1000 인지 확인
ip -br link                             # 로봇 연결 interface 이름 확인
git clone https://github.com/jinwoopark99/Dockerfile_unitreego2 ~/go2_docker
docker login                            # Docker Hub repo 가 private 인 경우만
```

- 로봇 interface 이름이 기본값 `enP8p1s0`과 다르면 host `~/.bashrc`에 지정해두면 편함.
  ```bash
  echo 'export ROBOT_IF=<interface 이름>' >> ~/.bashrc && source ~/.bashrc
  ```
- 이미지는 `docker-run.sh`가 없으면 자동으로 pull함.

---

## 1. 컨테이너 시작: `docker-run.sh`

```bash
cd ~/go2_docker
./docker-run.sh
```

| 명령 | 동작 |
|---|---|
| `./docker-run.sh` | 없으면 생성(+비밀번호 입력), 멈춰 있으면 start, 실행 중이면 그대로 |
| `./docker-run.sh --password` | sudo 비밀번호 변경 (재시작 없이 바로 적용) |
| `./docker-run.sh --recreate` | 삭제 후 새로 생성 (새 이미지 pull 후 사용, 비밀번호 다시 입력) |
| `./docker-run.sh --stop` | 정지 (컨테이너는 남아 있음) |
| `./docker-run.sh --rm` | 삭제 |

처음 생성할 때 화면:
```
== Set sudo password for container user 'unitree' (use a different one from your host account)
New password:
Retype new password:
== Creating go2 (image: mirgaon/go2-humble:latest, ROBOT_IF: enP8p1s0)
== sudo password set
== go2 is running

Enter:  docker exec -it -u unitree go2 bash
```

### 1-1. `docker-run.sh`가 하는 점검

| 점검 | 없을 때 |
|---|---|
| host UID 1000 | 경고 |
| `ROBOT_IF` interface 존재 | 경고 (`Network interface '...' not found`) |
| 이미지 | 자동 pull |
| nvidia runtime | 있을 때만 `--runtime nvidia` |
| `/dev/input`, `/dev/bus/usb` | 있을 때만 device 추가 |
| `/run/jtop.sock` | jetson-stats가 있을 때만 mount (없을 때 빈 디렉토리가 생기는 것 방지) |

### 1-2. 환경변수로 바꿀 수 있는 값

```bash
ROBOT_IF=eth0 ./docker-run.sh                                 # 로봇 interface (기본 enP8p1s0)
GO2_IMAGE=mirgaon/go2-humble:v2.0.0 ./docker-run.sh    # 특정 버전 이미지
GO2_CONTAINER=go2_test ./docker-run.sh                        # 컨테이너 이름 (기본 go2)
ROS_DOMAIN_ID=1 ./docker-run.sh                               # DDS domain (기본 0)
```

모두 **컨테이너를 만들 때** 적용됨. 이미 있는 컨테이너에 바꾸려면 `--recreate`.

### 1-3. sudo 비밀번호

```
./docker-run.sh (생성 시) → 비밀번호 입력 → docker exec 로 컨테이너 안에 설정 (chpasswd)
```

- **이미지에도, host 파일에도 저장하지 않음.** 컨테이너 안 `/etc/shadow`에만 존재.
- 비밀번호는 stdin으로만 전달 → 명령줄 기록, 환경변수, `docker inspect`에 남지 않음.
- 정지 / 재시작 / Jetson 재부팅 후 start: **유지됨**.
- 삭제(`--rm`, `--recreate`): 사라짐 → 다시 만들 때 새로 입력.
- 변경하거나 잊어버렸을 때: `./docker-run.sh --password` (기존 비밀번호 불필요).
- host 계정 비밀번호와 다르게 할 것.

### 1-4. 실행 옵션 (참고)

`docker-run.sh`가 붙이는 `docker run` 옵션.

| 옵션 | 목적 |
|---|---|
| `--network host`, `--ipc host`, `--pid host` | DDS (로봇 topic 수신) |
| `--hostname go2-dock`, `--add-host go2-dock:127.0.1.1` | 컨테이너 이름 표시, sudo의 hostname 경고 방지 |
| `--cap-add SYS_NICE`, `--ulimit rtprio=99`, `--ulimit memlock=-1` | 500 Hz 제어 loop의 real-time priority |
| `-v ${HOME}:${HOME}`, `-w ${HOME}` | host HOME을 같은 경로로 mount, 시작 경로 |
| `-e HOST_USER`, `-e HOST_GROUP`, `-e HOST_HOME` | entrypoint가 UID 1000 계정의 이름·group·HOME을 host 사용자와 같게 변경 |
| `-e ROBOT_IF`, `-e ROS_DOMAIN_ID` | DDS interface / domain |
| `-e DISPLAY`, `-e QT_X11_NO_MITSHM=1`, `-v /tmp/.X11-unix` | GUI (rviz2 등) |
| `--runtime nvidia`, `--device ...`, `-v /run/jtop.sock` | 있을 때만 (1-1 참고) |

---

## 2. 접속

```bash
docker exec -it -u $USER go2 bash
```

- `$USER`는 host 사용자 이름 (예: `unitree`). 컨테이너 안 사용자 이름도 같음 → 프롬프트 `unitree@go2-dock`.
- **`-u $USER`를 꼭 붙일 것.** 빼면 root shell로 들어감 (프롬프트가 `root@go2-dock`).
- `-u 1000`(UID)으로 써도 같음.
- 접속하면 HOME과 작업 경로가 host와 같고(`/home/unitree`), ROS2 / CycloneDDS / unitree 환경이 자동으로 잡힘.
- 터미널을 여러 개 열어도 각각 같은 명령으로 접속.

**alias 등록 (host에서 1회)**
```bash
echo "alias go2='docker exec -it -u \$USER go2 bash'" >> ~/.bashrc
source ~/.bashrc
go2
```

### 명령 하나만 실행

```bash
docker exec -it -u $USER go2 bash -ic 'ros2 topic list'
```

`bash -ic`의 `-i`가 필요함. ROS 환경 설정이 interactive shell에서만 읽히는 `/etc/bash.bashrc`에 있기 때문. `-i` 없이 실행하면 `ros2: command not found`.

### root가 필요할 때

```bash
sudo <명령>                     # 컨테이너 안에서, 생성 시 입력한 비밀번호
docker exec -it go2 bash        # 또는 host에서 root shell로 바로 접속
```

---

## 3. 종료 / 재시작 / 업데이트

| 상황 | 명령 |
|---|---|
| 정지 | `./docker-run.sh --stop` |
| 다시 시작 / Jetson 재부팅 후 | `./docker-run.sh` |
| 삭제 | `./docker-run.sh --rm` |
| 새 이미지로 교체 | `docker pull mirgaon/go2-humble:latest && ./docker-run.sh --recreate` |

- 내 파일은 모두 host HOME에 있어서, 컨테이너를 삭제해도 사라지지 않음.

---

## 4. 확인 명령

컨테이너 안에서:
```bash
id                                              # uid=1000(unitree) gid=1000(unitree)
whoami                                          # unitree
echo $HOME; pwd                                 # /home/unitree
echo $CYCLONEDDS_URI | grep -o 'name="[^"]*"'   # name="enP8p1s0"
sudo -v && echo SUDO_OK
ros2 topic list                                 # /lowstate, /sportmodestate
ros2 topic hz /lowstate                         # ~500 Hz
```

---

## 5. 자주 나오는 메시지

| 메시지 | 의미 / 대응 |
|---|---|
| 프롬프트가 `root@go2-dock` | `-u $USER`를 빠뜨림. 나가서 다시 접속 |
| 프롬프트가 `go2@go2-dock` | 예전 이미지/script로 만든 컨테이너. 새 이미지로 `./docker-run.sh --recreate` |
| `unable to find user unitree` | 컨테이너 시작 직후라 이름 변경 전. 1~2초 뒤 다시 접속 |
| `ros2: command not found` | non-interactive 실행. `bash -ic '...'` 사용 |
| `Error: No such container: go2` | 컨테이너가 없음. `./docker-run.sh` |
| `Network interface '...' not found` | `ip -br link`로 실제 이름 확인 후 `ROBOT_IF=<이름> ./docker-run.sh --recreate` |
| `Passwords do not match` | 두 번 입력한 비밀번호가 다름. 다시 실행 (컨테이너는 만들어지지 않음) |
| sudo 비밀번호가 틀렸다고 나옴 / 잊어버림 | host에서 `./docker-run.sh --password` |
| `ros2 topic list`에 로봇 topic 없음 | `CYCLONEDDS_URI`의 interface가 로봇 연결 interface와 같은지 확인 (`ROBOT_IF`) |
| `sudo: unable to resolve host go2-dock` | 예전 script로 만든 컨테이너. `./docker-run.sh --recreate` |
| rviz2 등 GUI가 `Authorization required` / `cannot open display` | 6번 참고 |
| `ros2 topic list` 결과가 이상함 (host에도 ROS2 설치된 경우) | 컨테이너 안에서 `ros2 daemon stop` 후 다시 실행 |

---

## 6. hostname과 GUI

컨테이너 hostname은 `go2-dock`.

- **이유**: 사용자 이름이 host와 같아서(`unitree`), hostname까지 같으면 프롬프트가 `unitree@ubuntu`로 완전히 같아짐 → host / 컨테이너 구분이 안 됨.
  ```
  unitree@ubuntu:~$      ← host
  unitree@go2-dock:~$    ← 컨테이너
  ```
- **ROS2 / DDS / unitree_sdk2 / sudo / 파일 권한**: hostname과 무관. 영향 없음.
- **GUI(X11) 앱만 영향 가능**: `~/.Xauthority`의 cookie가 host hostname(`ubuntu`) 기준으로 저장돼 있어서, 컨테이너(`go2-dock`)에서 GUI를 띄우면 인증에 실패할 수 있음.

| 해결 방법 | 방법 |
|---|---|
| A. host에서 권한 허용 (권장) | Jetson에 모니터 연결 시, host에서 `xhost +si:localuser:$USER` (재부팅하면 다시 실행) |
| B. hostname을 host와 같게 | `docker-run.sh`의 `--hostname go2-dock`과 `--add-host go2-dock:127.0.1.1`을 `--hostname "$(hostname)"`으로 바꾸고 `--recreate` (프롬프트 구분은 사라짐) |
