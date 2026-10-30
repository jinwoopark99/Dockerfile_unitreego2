# Dockerfile_unitreego2 v1 → v2 수정 내역

- 대상 repo: https://github.com/jinwoopark99/Dockerfile_unitreego2 (commit `70ad510`)
- 대상 이미지: Docker Hub `mirgaon/go2`
- 작성일: 2026-10-28
- 목표: **로컬 host 전용 이미지 → 어느 기기에서나 pull해서 쓰는 배포용 이미지**

## 최종 결과 (2026-10-29, Jetson 실기 검증 완료)

아래 "계획" 이후 실제 작업에서 바뀐 부분을 먼저 정리함. **현재 구조는 이 섹션과 `docs/image-architecture.md`가 기준.**

| # | 계획 | 최종 |
|---|---|---|
| 1 | 비밀번호: host `~/.go2_password` → compose secret → entrypoint 설정 | **파일 없이**, `docker-run.sh`가 컨테이너 생성 시 입력받아 `docker exec ... chpasswd`로 설정. entrypoint에서 비밀번호 코드 삭제 |
| 2 | `sudo make install` → `USER root` | 계획대로 |
| 3 | 고정 user `go2` (1000), workspace만 `/home/go2/go2_ws`로 mount | user는 계획대로. **mount는 host HOME 전체를 같은 경로로 (`${HOME}:${HOME}`)**, working dir `${HOME}`. entrypoint가 `usermod -d ${HOST_HOME} go2`로 HOME 변경. 환경 설정은 `/etc/bash.bashrc`로 이동 |
| 4 | CycloneDDS 소스 build 유지 | 계획대로 |
| 5 | `(rosdep init \|\| true)` | 계획대로 |
| 6 | `versions.env` 고정 | 계획대로 |
| 7 | sim `ROS_DOMAIN_ID` | 보류 (`ROS_DOMAIN_ID=1 ./docker-run.sh`로 대응 가능) |
| 8-1 | compose image 이름 → `mirgaon/go2:humble-jetson` | 계획대로 |
| 추가 | — | **`docker-run.sh` 추가 (기본 실행 방법)**: 생성/시작/정지/삭제, 비밀번호 설정, `ROBOT_IF` 기본값 `enP8p1s0`, `--add-host go2-dock:127.0.1.1`, nvidia runtime·device·jtop은 있을 때만 추가, 출력 메시지 영어 |
| 추가 | — | compose의 `secrets` 삭제. compose는 보조용 |
| 추가 | — | **컨테이너 안 사용자 이름을 host와 같게**: entrypoint가 UID 1000 계정(`go2`)을 `HOST_USER`/`HOST_GROUP`으로 이름 변경 (`usermod -l`, `groupmod -n`). 접속은 `docker exec -it -u $USER go2 bash` |
| 추가 | — | hostname은 `go2-dock` 유지 (host와 프롬프트 구분). GUI(X11) 인증 문제는 필요할 때 `xhost +si:localuser:$USER`로 대응 |

**검증 결과 (Go2 Jetson)**
- `./docker-run.sh --recreate` → 비밀번호 입력 → 생성 정상
- `sudo -v` 정상, 정지/재시작 후에도 비밀번호 유지
- HOME `/home/unitree`, host 파일 그대로 보임
- `ros2 topic hz /lowstate` ≈ 500 Hz

**남은 작업**
- [ ] 사용자 이름 변경 반영 이미지로 재build → `whoami`가 host 사용자인지 확인
- [ ] 보안 확인 (`/etc/shadow`의 UID 1000 계정이 `!`, `docker history` 검사)
- [ ] Jetson에서 수정한 파일 GitHub 반영 → PR merge → `v2.0.0` tag
- [ ] Docker Hub 기존 repo 삭제 → 재생성 → push (`humble-jetson`, `humble-jetson-v2.0.0`) → pull 테스트 → Public 전환
- [ ] 보류: 조이스틱 `input` group GID, sim domain, `build.sh` 메시지 영어화

---

## 계획 (작성 당시 기록)

| # | 항목 | 결정 |
|---|---|---|
| 1 | 비밀번호 설정 방식 | ✅ 수정: 이미지엔 비밀번호 없음 → **컨테이너 실행 시 각 기기 사용자가 설정** |
| 2 | `sudo make install` build 실패 가능성 | ✅ 수정: 해당 단계를 `USER root`로 실행 |
| 3 | 이미지가 build한 사람의 user/HOME에 묶임 | ✅ 수정: **고정 user `go2` (UID/GID 1000)**, 경로 고정 |
| 4 | CycloneDDS 소스 build | ⏸ 유지 (버전만 고정) |
| 5 | apt 단계 `\|\| true` 우선순위 버그 | ✅ 수정 |
| 6 | git clone 버전 고정 | ✅ 수정: 2026-10-28 기준 commit + `versions.env` |
| 7 | sim 사용 시 `ROS_DOMAIN_ID` 불일치 | ⏸ 보류 (sim 작업 시 처리) |
| 8-1 | compose의 `image:` 이름 | ✅ 수정: Docker Hub 이름으로 변경 |
| 8-2~5 | compose 나머지 (runtime, jtop, pid, hotplug) | ⏭ 보류 |

---

## 전체 구조 한눈에 보기

```
[build 시]  build.sh → Dockerfile
            - user go2 (1000:1000) 생성, 비밀번호 없음(잠김)
            - unitree_ros2 → /opt/unitree_ros2, unitree_sdk2 → /opt/unitree_robot
            - 모든 git clone은 versions.env의 commit으로 고정
            - 마지막 USER 지정 없음 → 컨테이너는 root로 시작

[기기마다 1회] host에 ~/.go2_password 파일 생성 (chmod 600)

[실행 시]   docker compose run --rm go2
            └─ entrypoint.sh (root)
                 ├─ /run/secrets/go2_password → chpasswd 로 go2 비밀번호 설정
                 └─ exec gosu go2 → 이후 bash/ros2/내 코드는 전부 go2로 실행
                      └─ entrypoint.sh (go2): ROS2 / CycloneDDS / unitree 환경 설정
```

| 파일 | 변경 요약 |
|---|---|
| `Dockerfile` | 고정 user `go2`, `/opt` 설치 경로, 비밀번호 단계 삭제, `gosu` 추가, `sudo make install` 제거, `\|\| true` 수정, commit 고정 |
| `build.sh` | USERNAME/UID/shadow 관련 코드 전부 삭제, `versions.env` 읽어서 전달, image 이름 변경 |
| `entrypoint.sh` | root 구간(비밀번호 설정 → gosu) 추가, unitree 경로 `/opt`로 변경 |
| `docker-compose.yml` | image 이름, `secrets:`, mount 경로 `/home/go2/...` |
| `versions.env` | 신규: 고정 commit 목록 |

---

## 1. 비밀번호: 컨테이너 실행 시 설정

**기존 문제**
- `build.sh`가 host의 `/etc/shadow` hash를 이미지에 복사함.
- 그 이미지를 push하면서 실제 계정 비밀번호 hash가 Docker Hub로 배포됨.

**변경**
- 이미지에는 비밀번호를 넣지 않음. `go2` 계정은 잠긴 상태(`!`)로 생성됨.
- 각 기기 사용자가 host에 비밀번호 파일을 만들어둠.
- compose가 이 파일을 컨테이너의 `/run/secrets/go2_password`로 전달함.
- entrypoint가 root 구간에서 `chpasswd`로 비밀번호를 설정함.
- 비밀번호는 실행 중인 컨테이너 안에만 존재함.
  - `--rm`으로 지우면 함께 사라짐.
  - 다음 실행 때 파일에서 다시 설정됨.

**host 준비 (기기마다 1회)**
```bash
printf '%s' '원하는비밀번호' > ~/.go2_password
chmod 600 ~/.go2_password
```

**docker-compose.yml**
```yaml
services:
  go2:
    secrets: [go2_password]

secrets:
  go2_password:
    file: ${HOME}/.go2_password
```

**entrypoint.sh 앞부분** (상세 코드는 3번 참고)
```bash
if [ -s /run/secrets/go2_password ]; then
    echo "go2:$(cat /run/secrets/go2_password)" | chpasswd
elif [ -t 0 ]; then
    echo "go2 sudo 비밀번호 설정:"; passwd go2
else
    echo "WARNING: 비밀번호 미설정 — sudo 불가" >&2
fi
```

- `passwd`로 직접 입력받는 분기는 compose 없이 `docker run -it`로 실행할 때를 위한 fallback임.
- `docker compose up -d`(백그라운드 실행)에서는 입력할 사람이 없으니 반드시 파일 방식을 사용할 것.

**기존 이미지 조치**
- 현재 push된 이미지에는 host 계정의 실제 hash가 들어 있음.
- public이면 private로 전환하고, 해당 계정 비밀번호를 변경할 것.
- 수정본을 push한 뒤에는 기존 tag를 삭제할 것.

---

## 2. `sudo make install` → `USER root`에서 실행

- build 중에는 TTY가 없어서 `sudo`가 비밀번호 입력을 기다리다 실패함.
- 게다가 1번 변경으로 build 시점의 `go2`에는 비밀번호도 없음.
- 따라서 root 권한이 필요한 build 단계는 모두 `USER root`에서 실행함.

```dockerfile
USER root
RUN git clone https://github.com/unitreerobotics/unitree_sdk2 /tmp/unitree_sdk2 \
    && git -C /tmp/unitree_sdk2 checkout ${UNITREE_SDK2_REF} \
    && cmake -S /tmp/unitree_sdk2 -B /tmp/unitree_sdk2/build -DCMAKE_BUILD_TYPE=Release \
    && cmake --build /tmp/unitree_sdk2/build -j2 \
    && cmake --install /tmp/unitree_sdk2/build \
    && rm -rf /tmp/unitree_sdk2
```

---

## 3. 고정 user `go2` (UID/GID 1000) + 경로 고정

### 3-1. 왜 UID 1000 고정인가
- Ubuntu와 JetPack에서 처음 만든 계정은 UID 1000임. Go2 Jetson 기본 계정 `unitree`도 1000.
- 사용할 기기의 `id -u`가 1000이면 mount한 `go2_ws`의 파일 권한이 자동으로 맞음.
- 1000이 아닌 기기가 생기면 그때 runtime UID 매핑을 추가 검토함.

### 3-2. 경로

| 대상 | 기존 | 변경 |
|---|---|---|
| 컨테이너 user | host `$USER` (build arg) | `go2` (1000:1000) |
| HOME | `/home/<host user>` | `/home/go2` |
| unitree_ros2 | `~/unitree_ros2` | `/opt/unitree_ros2` |
| unitree_sdk2 | `/opt/unitree_robot` | 유지 |
| workspace mount | `${HOME}/go2_ws:${HOME}/go2_ws` | `${HOME}/go2_ws:/home/go2/go2_ws` |
| rosbag mount | `${HOME}/go2_bags:${HOME}/go2_bags` | `${HOME}/go2_bags:/home/go2/go2_bags` |

- compose의 `${HOME}`은 host에서 해석되므로, 각 기기에서 자동으로 그 기기의 HOME이 들어감.
- 컨테이너 쪽 경로는 항상 `/home/go2/...`로 고정됨.

### 3-3. 왜 root로 시작하나
- 비밀번호 설정(`chpasswd`)은 root만 할 수 있음. 1번을 위해 entrypoint의 첫 부분만 root로 실행함.
- 설정 직후 `gosu`로 `go2`로 전환함. 실제 작업(bash, ros2, 내 코드)은 모두 `go2` 권한으로 실행됨.
- 부작용: image 기본 user가 root라서 `docker compose exec`로 새 shell에 들어갈 때 `-u go2`가 필요함.
  ```bash
  docker compose exec -u go2 go2 bash
  ```

### 3-4. Dockerfile (user 부분)

```dockerfile
# apt 목록에 gosu 추가
RUN groupadd --gid 1000 go2 \
    && useradd --uid 1000 --gid 1000 -m -s /bin/bash go2 \
    && usermod -aG sudo,dialout,input,plugdev,video go2
# 비밀번호 설정 RUN 블록 없음 (USERNAME / USER_UID / USER_GID / pwhash 전부 삭제)

# ... unitree_ros2 / unitree_sdk2 설치 (root) ...

RUN echo 'source /usr/local/bin/entrypoint.sh --env-only' >> /home/go2/.bashrc \
    && chown go2:go2 /home/go2/.bashrc
WORKDIR /home/go2
# USER 지정 없음 → root로 시작
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
```

### 3-5. entrypoint.sh 전체 흐름

```bash
#!/bin/bash
# --- [root 구간] 비밀번호 설정 후 go2로 전환 ---
if [ "$(id -u)" = "0" ] && [ "$1" != "--env-only" ]; then
    if [ -s /run/secrets/go2_password ]; then
        echo "go2:$(cat /run/secrets/go2_password)" | chpasswd
    elif [ -t 0 ]; then
        echo "go2 sudo 비밀번호 설정:"; passwd go2
    else
        echo "WARNING: 비밀번호 미설정 — sudo 불가" >&2
    fi
    exec gosu go2 "$0" "$@"          # go2로 entrypoint 재실행
fi

# --- [go2 구간] 환경 설정 (기존 내용, 경로만 변경) ---
source /opt/ros/humble/setup.bash
UNITREE_ROS2_DIR=/opt/unitree_ros2
[ -f "${UNITREE_ROS2_DIR}/cyclonedds_ws/install/setup.bash" ] && \
    source "${UNITREE_ROS2_DIR}/cyclonedds_ws/install/setup.bash"
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
ROBOT_IF="${ROBOT_IF:-eth0}"
export CYCLONEDDS_URI="<CycloneDDS><Domain><General><Interfaces>
  <NetworkInterface name=\"${ROBOT_IF}\" priority=\"default\" multicast=\"default\" />
</Interfaces></General></Domain></CycloneDDS>"
[ -f "${HOME}/go2_ws/install/setup.bash" ] && source "${HOME}/go2_ws/install/setup.bash"

if [ "$1" == "--env-only" ]; then return 0 2>/dev/null || exit 0; fi
exec "$@"
```

- 기존 entrypoint의 `${UNITREE_ROS2_DIR}/install/setup.bash` 줄은 삭제함. 항상 존재하지 않는 경로라 의미가 없었음.

---

## 4. CycloneDDS 소스 build: 유지

- 실기에서 검증된 조합이므로 현재 구조를 유지함.
- `rmw_cyclonedds`와 `cyclonedds`도 6번에 따라 commit으로 고정함.
- 경로만 `/opt/unitree_ros2/cyclonedds_ws`로 변경함.
- build는 root로 실행함. `/opt` 아래 설치물은 root 소유, go2는 읽기만 가능함.

---

## 5. apt 단계 `|| true` 버그 수정

- bash의 `&&`와 `||`는 우선순위가 같아서, 현재 코드는 `apt-get install`이 실패해도 build가 성공한 것처럼 넘어감.

```dockerfile
    && (rosdep init || true) \
    && rm -rf /var/lib/apt/lists/*
```

- 기존 `USER ${USERNAME}` 아래의 `RUN rosdep update`는 `go2`로 실행해야 함. 결과가 `~/.ros`에 저장되기 때문.
  ```dockerfile
  USER go2
  RUN rosdep update
  USER root
  ```

---

## 6. 버전 고정 (2026-10-28 기준)

| repo | 고정값 (commit) | 비고 |
|---|---|---|
| unitreerobotics/unitree_ros2 | `668d1ec5a05d1c38d3306bdca7d59f2ba3581a88` | 2026-07-02 |
| unitreerobotics/unitree_sdk2 | `d1abf001220d3e5f59e00a0c4aaa595e00089a4a` | 2026-10-15 |
| ros2/rmw_cyclonedds | `a58b9c56141f970e755e6bb2d2cae52843afdf13` | `humble` branch HEAD |
| eclipse-cyclonedds/cyclonedds | `5041f3560c088c99e5088b2b8520b69169621196` | `releases/0.10.x` HEAD |
| unitreerobotics/unitree_mujoco | `1eb6642e3f3fdfb7fb13a9794fd6a2dd93ea0e7d` | 2026-09-07, sim 이미지용 |

### `versions.env` (repo root에 추가)

```bash
UNITREE_ROS2_REF=668d1ec5a05d1c38d3306bdca7d59f2ba3581a88
UNITREE_SDK2_REF=d1abf001220d3e5f59e00a0c4aaa595e00089a4a
RMW_CYCLONEDDS_REF=a58b9c56141f970e755e6bb2d2cae52843afdf13
CYCLONEDDS_REF=5041f3560c088c99e5088b2b8520b69169621196
UNITREE_MUJOCO_REF=1eb6642e3f3fdfb7fb13a9794fd6a2dd93ea0e7d
```

### Dockerfile 적용 (unitree_ros2 부분)

```dockerfile
ARG UNITREE_ROS2_REF RMW_CYCLONEDDS_REF CYCLONEDDS_REF
RUN git clone https://github.com/unitreerobotics/unitree_ros2 /opt/unitree_ros2 \
    && git -C /opt/unitree_ros2 checkout ${UNITREE_ROS2_REF} \
    && cd /opt/unitree_ros2/cyclonedds_ws/src \
    && git clone https://github.com/ros2/rmw_cyclonedds \
    && git -C rmw_cyclonedds checkout ${RMW_CYCLONEDDS_REF} \
    && git clone https://github.com/eclipse-cyclonedds/cyclonedds \
    && git -C cyclonedds checkout ${CYCLONEDDS_REF} \
    && cd .. \
    && colcon build --packages-select cyclonedds --parallel-workers 2 \
    && source /opt/ros/humble/setup.bash \
    && colcon build --parallel-workers 2
```

**한계**
- ROS apt 패키지는 apt repo가 최신 버전만 유지하므로 완전히 고정되지 않음.
- 완전한 재현이 필요하면 Docker Hub 이미지의 tag와 digest를 기준으로 삼아야 함.

---

## 7. sim 사용 시 `ROS_DOMAIN_ID`: 보류

- unitree_mujoco 기본값은 `domain_id: 1`이고, 컨테이너 기본값은 0이라 topic이 서로 안 보임.
- sim 이미지 작업 시 `.env.sim`에 `ROS_DOMAIN_ID=1`을 넣거나 mujoco config를 변경해서 처리할 예정.

---

## 8-1. compose `image:` 이름

```yaml
services:
  go2:
    image: ${GO2_IMAGE:-mirgaon/go2:humble-jetson}   # 실제 push한 tag로 맞출 것
```

---

## build.sh (변경 후 전체)

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

BASE_IMAGE="${1:-nvcr.io/nvidia/l4t-jetpack:r36.4.0}"
IMAGE_TAG="${GO2_IMAGE:-mirgaon/go2:humble-jetson}"
set -a; source ./versions.env; set +a

echo "== Building ${IMAGE_TAG} (base: ${BASE_IMAGE})"
DOCKER_BUILDKIT=1 docker build \
    --build-arg BASE_IMAGE="${BASE_IMAGE}" \
    --build-arg UNITREE_ROS2_REF --build-arg UNITREE_SDK2_REF \
    --build-arg RMW_CYCLONEDDS_REF --build-arg CYCLONEDDS_REF \
    -t "${IMAGE_TAG}" .
```

- 다음 항목은 모두 삭제됨: sudo 비밀번호 입력, shadow 추출, USERNAME/UID 전달.

---

## 사용법 (변경 후)

```bash
# 기기마다 1회
id -u                                            # 1000인지 확인
mkdir -p ~/go2_ws ~/go2_bags
printf '%s' '비밀번호' > ~/.go2_password && chmod 600 ~/.go2_password
docker login                                     # private repo인 경우

# 실행
docker compose pull
docker compose run --rm go2                      # 대화형
docker compose up -d go2 && docker compose exec -u go2 go2 bash   # 상주
```

---

## 9. 검증 계획

| 단계 | 확인 내용 | 필요한 기기 |
|---|---|---|
| A | 기존 Hub 이미지에 실제 hash가 있는지 | Docker 있는 아무 PC |
| B | 수정본 로직 검증 | PC (`ubuntu:22.04` base로 build) |
| C | Jetson용 최종 이미지 build 및 push | Go2 Jetson |
| D | 실기 topic 확인 (`/lowstate` 약 500 Hz) | Go2 전원 ON + Jetson |

### A. 기존 이미지 확인 (PC에서, 실행 없이)

```bash
docker pull --platform linux/arm64 mirgaon/go2:<tag>
docker create --platform linux/arm64 --name chk mirgaon/go2:<tag>
docker cp chk:/etc/shadow ./shadow_check && docker rm chk
awk -F: '$2 !~ /^[*!]/ {print $1}' ./shadow_check   # 출력되면 hash 있음
rm ./shadow_check
```

### B. PC 검증 체크리스트

```bash
GO2_IMAGE=go2:test ./build.sh ubuntu:22.04
# compose의 runtime: nvidia 줄은 임시 주석 처리 (8-2 보류 상태)
```

- [ ] 새 이미지의 `/etc/shadow`에 `go2` hash가 없는지 (`!`인지) — 1번
- [ ] `~/.go2_password`가 있을 때 컨테이너 안에서 `sudo -v`가 그 비밀번호로 되는지 — 1번
- [ ] `~/.go2_password`가 없을 때 compose 동작 확인 (에러로 멈추는지, 경고 후 진행하는지) — 1번
- [ ] build가 sudo 없이 끝나는지 — 2번
- [ ] 컨테이너 안 `id`가 `uid=1000(go2)`이고, `go2_ws`에 만든 파일이 host에서 내 소유인지 — 3번
- [ ] `docker compose exec -u go2 go2 bash`에서 ROS 환경이 잡히는지 — 3번
- [ ] `ros2 interface list | grep unitree_go`가 보이는지 — 3, 4번
- [ ] `git -C /opt/unitree_ros2 rev-parse HEAD`가 versions.env 값과 같은지 — 6번
- [ ] apt 패키지 이름을 일부러 틀리게 넣었을 때 build가 실패하는지 — 5번
