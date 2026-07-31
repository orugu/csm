# csm (Custom SSH Management)

`~/.ssh/config`을 그룹으로 묶어서 fzf로 골라 접속하는 zsh 도구. 어느 머신에 복사해서
돌려도 동일하게 동작한다 — 그룹 분류가 하드코딩이 아니라 `~/.ssh/config`의 주석
기반이라서다.

## 설치

```sh
git clone https://github.com/orugu/csm.git
bash csm/install.sh
```

재실행해도 안전하다(idempotent) — 이미 설치돼 있으면 함수 파일만 최신으로 덮어쓰고
`~/.zshrc` 등록은 중복으로 안 한다. 새 터미널을 열거나 `source ~/.zshrc`.

### 필요한 것
- zsh
- [fzf](https://github.com/junegunn/fzf)
- `~/.ssh/config` (없으면 설치는 되지만 Host 항목을 먼저 만들어야 쓸모가 있음)

설치 스크립트가 fzf/zsh/`~/.ssh/config` 유무를 체크해서 없으면 안내만 하고(자동으로
sudo를 걸거나 하지 않음) 계속 진행한다.

## 명령

| 명령 | 하는 일 |
|---|---|
| `sm` | 전체 호스트를 flat 목록으로 fzf에서 골라 접속 |
| `csm` | 그룹 → 호스트 순으로 골라 접속 |
| `csm --mkdir` | 새 Host 항목을 대화형으로 추가 (그룹 선택 또는 새 그룹 생성) |
| `csm --add <ID@IP> [-p 포트] [-n 이름]` | 한 줄로 바로 Host 추가 (그룹 없이/기타로, 포트 생략 시 SSH 기본값 22, 이름 생략 시 IP를 별칭으로) |
| `csm --move` | 기존 호스트를 다른 그룹으로 이동 |
| `csm --tunnel` | 호스트를 골라 SSH 포트포워딩(-L 로컬 포워딩 / -D SOCKS) 열기 |
| `csm --status` | 등록된 모든 호스트에 병렬 접속해서 생존/응답시간/uptime/디스크 사용량 확인 |
| `csm --logs` | 여러 호스트를 멀티선택해서 로그를 동시에 tail (tmux 분할창 또는 접두어 방식) |
| `csm --graph` | ProxyJump 체인을 그룹별 트리로 시각화 |
| `csm --copy-id` | 호스트를 골라 `ssh-copy-id`로 공개키 등록 (다음부터 비밀번호 없이 접속) |
| `csm --setting` | fzf UI로 설정 값 변경 (`--reset`으로 초기화) |
| `csm --update` | GitHub에서 최신 버전으로 재설치 (원격이 실제로 더 높을 때만; `--force`로 강제 가능) |
| `csm --help`, `-h` | 도움말 |

### 업데이트 알림

`sm`/`csm` 메인 화면은 GitHub(`orugu/csm`)의 최신 태그를 확인해서(기본 6시간마다 캐시,
`update_check_interval_hours` 설정으로 조절) 새 버전이 있으면 화면 우측 상단에
"업데이트 있음 (vX.Y) - U: 지금 업데이트"를 띄운다. 그 자리에서 **U 키**를 누르면 바로
업데이트되고, `csm --update`로 수동 실행도 가능하다. 둘 다 재설치 후엔 새 터미널을
열거나 `source ~/.zshrc` 해야 적용된다(지금 켜져 있는 셸은 옛날 함수를 계속 씀).

### 설정 (`csm --setting`)

`~/.config/csm/settings.conf`(KEY=VALUE)에 저장되고 저장 즉시(새 터미널 없이) 다음 실행부터 반영된다.

| 키 | 기본값 | 설명 |
|---|---|---|
| `fzf_height` | 40 | 모든 fzf 메뉴의 높이(%) |
| `status_timeout` | 5 | `csm --status`의 호스트별 SSH 접속 타임아웃(초) |
| `status_workers` | 20 | `csm --status` 동시 접속 수 |
| `mkdir_default_port` | (없음) | `csm --mkdir`에서 Port를 비워둘 때 자동으로 채울 값 |
| `logs_mode` | auto | `csm --logs` 방식: `auto`(tmux 있으면 자동)/`tmux`/`prefix` |
| `copy_id_key` | (자동판별) | `csm --copy-id`에서 항상 쓸 공개키 경로 강제 지정 |

`csm --mkdir`로 새 호스트를 추가하면 바로 이어서 키를 등록할지 물어본다(같은 로직).
사용할 공개키는 그 호스트에 `IdentityFile`이 지정돼 있으면 그 키를 우선 쓰고, 없으면
`~/.ssh/*.pub` 중 내용이 실제로 유효한 공개키 형식인 것만 후보로 골라 쓴다(파일명만
`.pub`이고 내용이 이상한 파일은 자동으로 걸러진다).

각 서브커맨드는 `csm --<서브커맨드> --help`로 자세한 사용법을 볼 수 있다.

### 빠른 추가 (`csm --add`)

```sh
csm --add root@192.168.0.10                    # Port 생략 -> SSH 기본값 22, 별칭은 IP
csm --add root@192.168.0.10 -p 2222             # 포트 지정
csm --add -p 2222 root@192.168.0.10             # -p는 앞/뒤 순서 상관없음
csm --add root@192.168.0.10 -n myserver         # 별칭을 IP 대신 myserver로
csm --add -n myserver -p 2222 root@192.168.0.10 # -n/-p 둘 다 순서 상관없음
```

`ID@IP` 형식으로 파싱해서 `User`/`HostName`을 채운다. `-p`를 생략하면 `~/.ssh/config`에
`Port` 줄 자체를 안 남긴다(SSH 기본값 22가 그대로 적용됨). `-n`을 생략하면 별칭으로 IP를
그대로 쓴다. 그룹 없이(`csm --mkdir`의 "기타" 취급과 동일하게) 추가된다.

## 그룹 분류 방식

`~/.ssh/config`에 `Host` 블록 위에 이 주석을 달아두면 그 그룹으로 묶인다:

```
# csm-group: 회사
Host work-server
    HostName 10.0.0.5
    User me
```

`# csm-group:` 주석이 하나도 없으면 `csm`은 `sm`과 동일하게 flat 목록으로 동작한다
(에러 아님, 정상 동작). 그룹이 1개뿐이어도 마찬가지로 flat 목록으로 동작한다.

`csm --mkdir`/`csm --move`는 `~/.ssh/config`를 고치기 전에 항상
`~/.ssh/config.bak.<타임스탬프>`로 백업을 남긴다.

## 알려진 제한

- 한 `Host` 줄에 별칭이 여러 개 있는 경우(`Host a b c`) `csm --move`는 그 줄 전체를
  통째로 옮긴다 — 별칭 하나만 골라서 그룹을 분리할 수는 없다.
- zsh 전용이다 (bash 호환 보장 안 함).
