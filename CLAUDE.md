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
- `csm --mkdir`/`csm --move`가 `~/.ssh/config`를 수정하는 로직은 파이썬(`python3 -`
  heredoc)으로 짜여 있다. 로컬 테스트 중 실제로 잡은 버그: Host 블록 텍스트를
  파이프(stdin)로 넘기려 했는데 파이썬 스크립트 자체도 heredoc으로 stdin을 쓰고 있어서
  충돌했다(파이프가 무시됨) — 지금은 블록을 argv로 넘기도록 고쳐져 있다. 이 파일을
  수정할 일이 있으면 같은 함정을 다시 만들지 않도록 주의.
- `csm --mkdir`/`csm --move`는 항상 `~/.ssh/config.bak.<타임스탬프>`로 백업 후
  수정한다 — SSH 설정 파일이라 실수하면 접속 자체가 막히는 파일이므로, 이 로직을
  건드릴 땐 반드시 **원본 파일이 아니라 임시 복사본**으로 먼저 검증할 것
  (`cp ~/.ssh/config /tmp/test_config` 해서 그걸로 실험).

## 알려진 제한 (일부러 안 고친 것, 버그 아님)

- 한 `Host` 줄에 별칭이 여러 개(`Host a b c`)면 `csm --move`는 통째로 옮긴다.
- `csm-group:` 주석이 없거나 그룹이 1개뿐이면 `csm`은 `sm`(flat 목록)과 동일하게 동작한다.
  이건 정상 동작이지 에러가 아니다.
- zsh 전용. bash에서의 동작은 보장 안 함.
