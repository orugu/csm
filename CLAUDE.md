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

## 알려진 제한 (일부러 안 고친 것, 버그 아님)

- 한 `Host` 줄에 별칭이 여러 개(`Host a b c`)면 `csm --move`는 통째로 옮긴다.
- `csm-group:` 주석이 없거나 그룹이 1개뿐이면 `csm`은 `sm`(flat 목록)과 동일하게 동작한다.
  이건 정상 동작이지 에러가 아니다.
- zsh 전용. bash에서의 동작은 보장 안 함.
