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
| `csm --move` | 기존 호스트를 다른 그룹으로 이동 |
| `csm --tunnel` | 호스트를 골라 SSH 포트포워딩(-L 로컬 포워딩 / -D SOCKS) 열기 |
| `csm --status` | 등록된 모든 호스트에 병렬 접속해서 생존/응답시간/uptime/디스크 사용량 확인 |
| `csm --logs` | 여러 호스트를 멀티선택해서 로그를 동시에 tail (tmux 분할창 또는 접두어 방식) |
| `csm --graph` | ProxyJump 체인을 그룹별 트리로 시각화 |
| `csm --copy-id` | 호스트를 골라 `ssh-copy-id`로 공개키 등록 (다음부터 비밀번호 없이 접속) |
| `csm --help`, `-h` | 도움말 |

`csm --mkdir`로 새 호스트를 추가하면 바로 이어서 키를 등록할지 물어본다(같은 로직).
사용할 공개키는 그 호스트에 `IdentityFile`이 지정돼 있으면 그 키를 우선 쓰고, 없으면
`~/.ssh/*.pub` 중 내용이 실제로 유효한 공개키 형식인 것만 후보로 골라 쓴다(파일명만
`.pub`이고 내용이 이상한 파일은 자동으로 걸러진다).

각 서브커맨드는 `csm --<서브커맨드> --help`로 자세한 사용법을 볼 수 있다.

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
