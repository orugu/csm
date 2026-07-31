# csm (Custom SSH Management)

`~/.ssh/config`를 그룹으로 묶어서 fzf로 골라 접속하는 zsh 도구. 다른 세션/다른 컴퓨터의
Claude가 이 저장소를 받아서 그대로 설치해도 되도록 만든 self-contained 설치 스크립트다.

## 설치 (그대로 실행하면 됨, 추가 질문 없이 진행 가능)

```sh
git clone https://github.com/orugu/csm.git
bash csm/install.sh
```

이 두 줄이 전부다. `install.sh`는:
1. zsh/fzf/`~/.ssh/config` 유무를 체크하고 없으면 **안내만** 한다(자동 설치나 sudo 실행 안 함 —
   임의로 `brew install`/`apt install`을 sudo로 돌리는 코드는 의도적으로 안 넣었음).
2. `~/.config/zsh/ssh-picker.zsh`에 `sm`/`csm` 함수를 설치(덮어쓰기).
3. `~/.zshrc`에 그 파일을 source하는 한 줄을 추가한다 — **이미 등록돼 있으면 건드리지 않는다**
   (문자열 `grep -qF`로 확인). 즉 여러 번 실행해도 안전(idempotent).

설치 후 새 터미널을 열거나 `source ~/.zshrc` 하면 `sm`/`csm` 명령을 바로 쓸 수 있다.
`csm --help`로 자체 도움말을 볼 수 있다.

## 설치 후 확인 방법 (검증 없이 "완료"라고 보고하지 말 것)

`getSlide`/`summary` 원칙과 동일하게, 설치했다고 보고하기 전에 반드시 확인한다:

```sh
zsh -ic 'source ~/.zshrc; type sm; type csm; csm --help'
```

`sm`/`csm`이 `~/.config/zsh/ssh-picker.zsh`에서 온 shell function으로 뜨는지 확인.

## 이 컴퓨터(원본, 2026-07-30)에 실제로 적용했을 때 있었던 것들

- 이 저장소를 만들기 전, 원본 머신의 `csm`은 `~/.zshrc`에 그룹이 하드코딩돼 있었다
  (`groups=("Tailscale" "devlovers-ts" ...)` 식). 그걸 지금의 "`~/.ssh/config`에
  `# csm-group: 이름` 주석을 다는 방식"으로 마이그레이션했고, 15개 호스트 전부
  `ssh -G <host>`로 재검증해서 무손실 이전을 확인했다. 다른 머신에 새로 설치할 때는
  이 마이그레이션이 필요 없다 — 처음부터 `# csm-group:` 방식으로 시작하면 된다.
- **`python3 - <<'PYEOF' ... PYEOF`에 파이프로 데이터를 같이 넘기면 안 된다 — 두 번 실제로
  잡은 버그다.** `python3 -`는 stdin에서 실행할 스크립트를 읽는데, `foo | python3 - <<'EOF'`
  처럼 파이프와 heredoc을 동시에 fd0에 걸면 **파이프가 이긴다**(heredoc이 아니라!) — 즉
  `python3 -`가 heredoc에 적어둔 파이썬 코드가 아니라 파이프로 들어온 데이터를 "실행할
  스크립트"로 착각해서 읽어버린다. 실측(2026-07-30): `printf 'host1\n' | python3 - <<'EOF'
  import sys; ... EOF` 를 돌리면 `NameError: name 'host1' is not defined`가 난다 —
  heredoc의 파이썬 코드는 통째로 무시되고 파이프 데이터 "host1"이 코드로 해석된 것.
  `--mkdir`(Host 블록 텍스트)과 `--status`(호스트 목록) 양쪽에서 실제로 이 버그를 만들고
  고쳤다. **해결책은 항상 동일: 파이프 쓰지 말고 데이터를 `python3 - <스크립트경로없이
  바로_인자로> <<'PYEOF'` 식으로 argv로 넘겨서 `sys.argv[N]`으로 읽을 것.** 이 파일을
  다시 수정할 때 같은 함정을 세 번째로 만들지 않도록 주의.
- `csm --mkdir`/`csm --move`는 항상 `~/.ssh/config.bak.<타임스탬프>`로 백업 후
  수정한다 — SSH 설정 파일이라 실수하면 접속 자체가 막히는 파일이므로, 이 로직을
  건드릴 땐 반드시 **원본 파일이 아니라 임시 복사본**으로 먼저 검증할 것
  (`cp ~/.ssh/config /tmp/test_config` 해서 그걸로 실험).
- **`csm --logs`의 tmux 경로는 이 저장소를 만든 원본 머신에 tmux 자체가 안 깔려있어서
  실측 검증을 못 했다.** tmux 없을 때의 대체 경로(각 줄 앞에 `[호스트명]` 접두어 붙여서
  합치는 방식)는 실제 호스트 3개로 동시 접속해서 정상 동작 확인했지만, `tmux new-session`/
  `split-window`/`select-layout tiled`/`attach` 시퀀스는 표준 tmux CLI 문법대로 작성만
  하고 실제 tmux 환경에서 돌려보지는 않았다. tmux가 있는 환경에서 처음 쓸 때는 이 경로가
  기대대로 동작하는지 확인부터 할 것.

- `csm --copy-id`(v1.6)의 IdentityFile 감지는 `ssh -G <host> | awk '/^identityfile /
  {print $2; exit}'`로 첫 번째 줄만 쓴다. 호스트에 `IdentityFile`을 명시적으로 지정해두면
  `ssh -G`가 그것만 보여줘서 정확히 잡히지만(실측 확인: hapcheon), 명시 안 해둔 호스트는
  `ssh -G`가 OpenSSH 기본 후보 목록(id_rsa, id_ecdsa, id_ecdsa_sk, id_ed25519, ...)을
  순서대로 다 보여주는데 그중 첫 번째(보통 id_rsa)만 본다 — id_rsa.pub이 없는 ed25519 전용
  환경에서는 `_csm_is_valid_pubkey`가 파일 존재 자체를 확인하니 자연스럽게 실패해서
  `_csm_find_pubkeys` 폴백으로 넘어가긴 하지만(실측 확인: Tasha-personal), 만약 id_rsa.pub과
  id_ed25519.pub이 둘 다 있는 환경이면 사용자가 실제로 원하는 키가 아니라 그냥 첫 번째로
  발견된 기본 키를 오판해서 쓸 수 있다 — 이 경우엔 `--copy-id` 실행 시 나오는 "등록할 키: ..."
  줄을 보고 원치 않는 키면 Ctrl+C로 취소할 것.
- `csm --setting`(v1.7)은 `~/.config/csm/settings.conf`(KEY=VALUE)를 매 함수 호출마다
  새로 읽는다(캐싱 안 함) — 그래서 설정 바꾸면 같은 터미널에서 바로 다음 실행부터
  반영된다. `_csm_get_setting`/`_csm_set_setting` 실측 검증(2026-07-31): 저장/조회/덮어쓰기
  (중복 라인 안 생김) 확인, `copy_id_key`에 무효한 값을 넣었을 때 경고 후 자동판별로
  폴백하는 것과 유효한 값을 넣었을 때 그걸 바로 쓰는 것 둘 다 실제 호스트로 확인,
  `logs_mode=tmux`인데 tmux가 실제로 없는 환경에서 경고 후 prefix로 폴백하는 것도 확인.
  `status_timeout`/`status_workers`는 파이프가 아니라 `python3 - <데이터> <timeout> <workers>
  <<'PYEOF'` 식으로 전부 argv로 넘긴다 — 위에 적어둔 stdin 충돌 함정을 이 함수를 만들 때도
  똑같이 피해야 했음.
- **`csm --update`/버전 알림(v1.8)**: `_CSM_VERSION`(sourced 파일 안의 변수)과 GitHub 태그
  (`git ls-remote --tags`로 확인, vX.Y 형식만 인식)를 비교한다. 캐시(`~/.config/csm/update_cache`)를
  둬서 매번 원격을 안 때리고 `update_check_interval_hours`(기본 6시간)마다만 재확인한다.
  fzf의 `U` 키 바인딩(`--bind "U:execute(zsh -ic 'csm --update')"`)은 **반드시 `zsh -ic`로
  새 인터랙티브 셸을 띄워서 실행해야 한다** — fzf의 execute()는 새 프로세스라서 zsh 함수
  정의(csm 등)를 상속 못 하는데, `-i`로 띄우면 `~/.zshrc`를 다시 읽어서 `csm`이 정의된다.
  이 파일을 고칠 때 이 부분을 `execute(csm --update)`처럼 단순화하면 "command not found: csm"
  으로 깨진다 — 잊지 말 것.
  실측 검증(2026-07-31): 로컬 버전(1.8, 아직 태그 안 붙인 개발 중 버전)이 원격 최신 태그(v1.7)보다
  높을 때 `_csm_update_available`이 정확히 "업데이트 없음"(exit 1)을 반환하는 것, 캐시를 조작해서
  원격이 더 높은 상황을 흉내냈을 때 "업데이트 있음"(exit 0) + 헤더 문자열이 정확히 만들어지는 것,
  실제로 `git clone` + `install.sh` 재실행까지 전체 파이프라인이 동작하는 것(v1.7로 실제 재설치됐다가
  로컬 v1.8로 재설치해서 원복)까지 확인함. 우측 정렬용 `$COLUMNS`가 비-tty 환경에서 "0"으로
  설정돼있어(unset이 아니라서 `${COLUMNS:-80}` 폴백이 안 먹음) 정렬이 깨지는 것도 실측으로
  발견해서 `[ "$cols" -le 0 ] && cols=80`로 방어함.
- **v1.9 버그 수정 4건** (전체 코드 리뷰로 발견, 전부 실측 재현 후 수정):
  1. `csm --update`가 버전 비교 없이 무조건 `git clone` + 재설치했다 — 로컬이 원격보다
     같거나 앞서 있어도(예: 태그 안 붙인 개발 중 버전) 그냥 덮어써서 조용히 다운그레이드될
     위험이 있었다. `_csm_version_gt()`로 비교해서 원격이 실제로 더 높을 때만 진행하고,
     아니면 "이미 최신 버전입니다"라고 알리고 끝내도록 수정. 강제로 하고 싶으면 `--force`.
  2. `csm --logs`의 tmux 경로가 `$cmd`를 그냥 `'$cmd'`로 감싸서 tmux 명령 문자열에
     끼워넣었는데, `$cmd` 자체에 작은따옴표가 들어있으면(`grep 'ERROR'` 같은 흔한 패턴)
     감싸는 따옴표가 조기 종료되어 ssh에 명령이 여러 조각으로 쪼개져 전달되는 버그.
     실측 확인: `sh -c`로 재파싱해보니 실제로 인자가 깨져서 나뉨. 수동 백슬래시 이스케이프로
     고치려다 그것도 잘못 만들 뻔해서(재현 테스트에서 `\'\'\'ERROR\'\'\'`처럼 꼬임을 확인),
     zsh 내장 `${(q)cmd}`(셸이 다시 파싱해도 원본 그대로 한 덩어리로 복원됨, `sh -c`로
     재검증함)로 교체 — **수동 quote-escaping을 직접 짜지 말고 `${(q)var}`를 쓸 것**.
  3. `csm --graph`에서 ProxyJump가 순환(A→B→A)이면 그 호스트들과 거기 의존하는
     호스트까지 트리 출력에서 통째로 조용히 사라지는 버그(무한재귀가 아니라 데이터 누락 —
     순환에 걸린 노드는 서로가 서로의 자식이 되어 버려서 애초에 루트 목록에 안 들어가고,
     `print_tree`는 루트에서만 시작하니 아예 방문을 안 함, 실측: 2노드 순환 만들어서 재현
     확인). "도달 불가" 집합(`set(hosts) - visited`)을 계산해서 별도 섹션으로 경고 출력하게
     수정. `print_tree`에도 `_seen` 방문 집합을 추가해서(현재 구조상 발생 안 하지만) 혹시
     나중에 사이클이 루트에서 도달 가능해지는 방향으로 코드가 바뀌어도 무한재귀로 안 죽게
     이중 방어해둠.
  4. `csm --setting`에서 숫자여야 하는 설정(`status_timeout`/`status_workers`/
     `update_check_interval_hours`/`mkdir_default_port`/`fzf_height`)에 값 검증이 없어서,
     숫자 아닌 값이나 범위 밖 값을 넣으면 저장은 되고 나중에 `csm --status` 등에서
     파이썬 `int()` 변환이 그대로 터져서 크래시로 이어지던 문제. 저장 전에 정규식/범위
     체크해서 걸러내도록 수정(실측: `abc`, `-5`, `fzf_height=150/0` 다 거부되고 유효값만
     저장되는 것 확인).

- **v1.10 버그 수정 5건** (전체 재점검으로 발견, 전부 실측 재현 후 수정):
  1. **v1.9에서 고친 숫자 설정값 크래시가 "UI에서만" 막혀있었다** — `csm --setting`을
     거치면 검증되지만, `~/.config/csm/settings.conf`를 텍스트 에디터로 직접 편집해서
     `status_timeout=abc` 같은 값을 넣으면 여전히 `csm --status`가 `int()`에서 터졌다
     (실측 재현). 근본 수정: `csm --status`의 python heredoc 안에서 `int()` 변환을
     `_safe_int()`(try/except, 실패하면 기본값+stderr 경고)로 감싸고, `_csm_refresh_update_cache_if_stale`의
     `update_check_interval_hours`와 `_csm_mkdir`의 `mkdir_default_port`도 값을
     **실제로 쓰는 지점**에서 정규식 검증하도록 방어를 추가했다. **교훈: 입력 검증은
     UI 진입점이 아니라 값을 실제로 소비하는 지점에 둬야 한다** — 설정 파일은 UI를
     거치지 않고도 언제든 직접 고쳐질 수 있다.
  2. `_csm_tunnel`에서 `$host`를 `printf`의 포맷 문자열 자리에 직접 넣어서, 호스트
     별칭에 `%`가 있으면 깨지던 것 — `printf "%s" "$host"`로 인자 분리.
  3. `_csm_tunnel`의 `-L` 로컬 포워딩에서 원격 호스트로 IPv6 리터럴(`::1`, `fe80::1`)을
     주면 `local:remote:port` 콜론 파싱이 깨지던 것 — 콜론이 있으면 `[::1]`처럼
     대괄호로 감싸도록 수정(이미 대괄호가 있으면 중복으로 안 감쌈).
  4. `_csm_logs`의 prefix(tmux 없음) 모드에서 `sed "s/^/[$h] /"`가 호스트 별칭에
     `&`가 있으면 그 `&`가 sed의 "매치된 전체" 특수문자로 해석돼서 조용히 사라지던 것
     (실측: `host&name` -> `hostname`으로 잘림) — `$h`를 sed 치환문자열에 넣기 전에
     `&` -> `\&`로 이스케이프.
  5. `csm <대시로 안 시작하는 인자>`(예: `csm status`처럼 `--`를 빼먹은 오타)를 아무
     경고 없이 무시하고 기본 메뉴로 들어가던 것 — `case`문에 `""`(인자 없음, 정상)와
     `*`(그 외 전부, 에러)를 명시적으로 나눠서 오타를 안내하도록 수정.

## 알려진 제한 (일부러 안 고친 것, 버그 아님)

- 한 `Host` 줄에 별칭이 여러 개(`Host a b c`)면 `csm --move`는 통째로 옮긴다.
- `csm-group:` 주석이 없거나 그룹이 1개뿐이면 `csm`은 `sm`(flat 목록)과 동일하게 동작한다.
  이건 정상 동작이지 에러가 아니다.
- zsh 전용. bash에서의 동작은 보장 안 함.
- 업데이트 알림의 `U` 키 바인딩은 fzf의 검색어 입력과 같은 키 입력창을 공유한다 —
  호스트/그룹 이름에 대문자 `U`가 들어가는 걸 타이핑하려고 하면 그 U가 검색어로 안 가고
  업데이트 실행으로 가로채질 수 있다. 사용자가 명시적으로 요청한 키 배정이라 그대로 뒀다.
