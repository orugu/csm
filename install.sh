#!/usr/bin/env bash
# sm / csm (Custom SSH Management, fzf 기반 SSH 접속정보 관리/접속 도구) 설치 스크립트.
# version 1.10 (2026-07-31)
#
# 사용법:
#   git clone https://github.com/orugu/csm.git && bash csm/install.sh
#
# 무엇을 하는가:
#   1) fzf, ~/.ssh/config 존재 여부 체크(없으면 안내만 하고 설치는 강행)
#   2) ~/.config/zsh/ssh-picker.zsh 파일에 sm/csm 함수 정의를 설치
#   3) ~/.zshrc에 해당 파일을 source하는 한 줄을 추가(이미 있으면 중복 추가 안 함)
#
# 재실행해도 안전(idempotent) — .zshrc에 이미 등록돼 있으면 건드리지 않고,
# ssh-picker.zsh 파일은 최신 버전으로 덮어쓴다(기능 업데이트 시 재실행해서 갱신 가능).
#
# 어떤 머신에 복사해서 돌려도 동일하게 동작하도록, csm의 그룹 분류는
# 하드코딩 대신 ~/.ssh/config의 "# csm-group: 그룹이름" 주석을 읽어서 구성한다.
# 그런 주석이 전혀 없으면 csm은 그냥 sm과 동일한 flat 목록으로 동작한다(정상 동작, 에러 아님).
#
# 설치되는 명령:
#   sm              전체 호스트 flat 목록에서 골라 접속
#   csm             그룹 -> 호스트 순으로 골라 접속
#   csm --mkdir     새 Host 항목을 대화형으로 추가 (그룹 지정/새 그룹 생성 가능)
#   csm --move      기존 호스트를 다른 그룹으로 이동
#   csm --tunnel    호스트를 골라 SSH 포트포워딩(-L/-D) 열기
#   csm --status    등록된 모든 호스트 생존/응답시간/uptime/디스크 사용량 확인
#   csm --logs      여러 호스트 로그를 동시에 tail(tmux 분할창/접두어 방식)
#   csm --graph     ProxyJump 체인을 트리로 시각화
#   csm --copy-id   호스트를 골라 ssh-copy-id로 공개키 등록
#   csm --setting   fzf UI로 각종 설정 값 변경(메뉴 높이, --status 타임아웃 등)
#   csm --update    GitHub에서 최신 버전으로 재설치 (새 버전 있으면 sm/csm 화면에서 U키로도 가능)
#   csm --help, -h  도움말
#
# csm --mkdir/--move는 ~/.ssh/config를 고치기 전 항상 ~/.ssh/config.bak.<타임스탬프>로 백업한다.

set -e

TARGET_DIR="$HOME/.config/zsh"
TARGET_FILE="$TARGET_DIR/ssh-picker.zsh"
ZSHRC="$HOME/.zshrc"

echo "== sm/csm(SSH 호스트 피커) 설치 =="
echo

# 1) 의존성 체크 (설치는 안 하고 안내만 함 - 실행 환경에 임의로 sudo를 걸지 않기 위함)
if ! command -v zsh >/dev/null 2>&1; then
  echo "경고: zsh가 안 보입니다. 이 도구는 zsh 전용입니다(bash에서는 동작 보장 안 함)."
fi

if ! command -v fzf >/dev/null 2>&1; then
  echo "경고: fzf가 안 보입니다. 설치 후 사용하세요."
  if command -v brew >/dev/null 2>&1; then
    echo "  -> brew install fzf"
  elif command -v apt >/dev/null 2>&1; then
    echo "  -> sudo apt install fzf"
  else
    echo "  -> https://github.com/junegunn/fzf#installation 참고"
  fi
  echo
fi

if [ ! -f "$HOME/.ssh/config" ]; then
  echo "경고: ~/.ssh/config 가 없습니다. Host 항목을 미리 만들어두면 바로 쓸 수 있습니다."
  echo
fi

# 2) 함수 파일 설치
mkdir -p "$TARGET_DIR"
cat > "$TARGET_FILE" <<'ZSHEOF'
# sm / csm: fzf 기반 SSH 접속정보 관리/접속 도구. ~/.ssh/config만 있으면 동작한다.
# csm = Custom SSH Management.
#
# sm         : ~/.ssh/config의 모든 Host를 flat하게 fzf로 골라서 접속
# csm        : "# csm-group: 그룹이름" 주석 기준으로 그룹 -> 호스트 2단계 메뉴로 접속
#              (csm-group 주석이 없거나 그룹이 1개뿐이면 sm과 동일하게 동작)
# csm --mkdir: 새 Host 항목을 대화형으로 추가(그룹 선택/새 그룹 생성 가능)
# csm --move : 기존 호스트를 다른 그룹으로 이동
# csm --tunnel: 호스트를 골라 SSH 포트포워딩(-L 로컬 포워딩 / -D SOCKS) 열기
# csm --status: 등록된 모든 호스트에 병렬 SSH 접속해서 생존/응답시간/uptime/디스크 사용량 표로 확인
# csm --logs  : 여러 호스트를 멀티선택해서 로그를 동시에 tail(tmux 있으면 분할창, 없으면 접두어 방식)
# csm --graph : Host의 ProxyJump 관계를 그룹별 트리로 시각화
# csm --copy-id: 호스트를 골라 ssh-copy-id로 공개키 등록(--mkdir 직후에도 물어봄)
# csm --setting: fzf UI로 각종 설정 값 변경
# csm --update : GitHub에서 최신 버전으로 재설치(새 버전 있으면 메인 화면에 U키 알림)
# csm --help : 도움말
#
# 예시 ~/.ssh/config:
#   # csm-group: 개인
#   Host my-nas
#       HostName 192.168.0.10
#
#   # csm-group: 회사
#   Host work-server
#       HostName 10.0.0.5
#
# --mkdir/--move는 파일을 고치기 전에 항상 ~/.ssh/config.bak.<타임스탬프>로 백업을 남긴다.
# 여러 별칭이 한 Host 줄에 같이 있는 경우(예: "Host a b c") --move는 그 줄 전체를 통째로 옮긴다.

_CSM_VERSION="1.10"
_CSM_REPO_SSH="git@github.com:orugu/csm.git"
_CSM_UPDATE_CACHE="$HOME/.config/csm/update_cache"

# --- 업데이트 확인/알림/실행 ------------------------------------------------
# GitHub 태그(vX.Y 형식)를 확인해서 현재 버전보다 높은 게 있으면 sm/csm 메인 화면에
# 알림을 띄우고, U 키(또는 csm --update)로 바로 재설치할 수 있게 한다.
# 매번 원격을 확인하면 fzf 뜨는 속도가 느려지니, 캐시 파일(update_cache)에
# "checked_at=<epoch>\nlatest=<vX.Y>"로 저장해두고 update_check_interval_hours(기본 6)
# 시간이 지났을 때만 다시 확인한다.

_csm_remote_version() {
  GIT_SSH_COMMAND="ssh -o ConnectTimeout=3 -o BatchMode=yes" \
    git ls-remote --tags "$_CSM_REPO_SSH" 2>/dev/null \
    | awk -F'refs/tags/' '{print $2}' \
    | grep -E '^v[0-9]+\.[0-9]+$' \
    | sort -V | tail -1
}

_csm_cached_latest() {
  [ -f "$_CSM_UPDATE_CACHE" ] || return
  awk -F= '$1=="latest"{print $2}' "$_CSM_UPDATE_CACHE"
}

_csm_cache_checked_at() {
  if [ -f "$_CSM_UPDATE_CACHE" ]; then
    awk -F= '$1=="checked_at"{print $2}' "$_CSM_UPDATE_CACHE"
  else
    echo 0
  fi
}

_csm_write_update_cache() {
  mkdir -p "$(dirname "$_CSM_UPDATE_CACHE")"
  { echo "checked_at=$(date +%s)"; echo "latest=$1"; } > "$_CSM_UPDATE_CACHE"
}

_csm_refresh_update_cache_if_stale() {
  local now checked_at interval_hours interval
  now=$(date +%s)
  checked_at=$(_csm_cache_checked_at)
  interval_hours=$(_csm_get_setting update_check_interval_hours 6)
  # settings.conf를 직접 편집해서 숫자가 아닌 값을 넣었을 때의 방어(csm --setting UI를
  # 거치면 이미 막히지만, 파일을 텍스트 에디터로 직접 고치면 그 검증을 우회할 수 있다).
  [[ "$interval_hours" =~ ^[0-9]+$ ]] && [ "$interval_hours" -gt 0 ] || interval_hours=6
  interval=$(( interval_hours * 3600 ))
  if (( now - checked_at >= interval )); then
    local remote
    remote=$(_csm_remote_version)
    [ -n "$remote" ] && _csm_write_update_cache "$remote"
  fi
}

# a가 b보다 (버전으로) 더 높으면 성공(0). "1.8" 같은 X.Y 형식 문자열을 받는다(v 접두어 없이).
_csm_version_gt() {
  local a="$1" b="$2"
  [ "$a" = "$b" ] && return 1
  [ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -1)" = "$a" ]
}

# 새 버전이 있으면 성공(0), 없으면 실패(1) - 캐시가 오래됐으면 이 안에서 새로 확인한다.
_csm_update_available() {
  _csm_refresh_update_cache_if_stale
  local latest latest_num
  latest=$(_csm_cached_latest)
  [ -z "$latest" ] && return 1
  latest_num="${latest#v}"
  _csm_version_gt "$latest_num" "$_CSM_VERSION"
}

# sm/csm 메인 화면 fzf에 넘길 --header/--bind 인자를 전역 배열 _CSM_UPD_ARGS에 채운다
# (업데이트 없으면 빈 배열). eval 없이 그냥 전역 배열 하나 쓰는 게 훨씬 덜 위험해서
# 이렇게 함 - 호출부에서는 `_csm_update_fzf_args; ... "${_CSM_UPD_ARGS[@]}" ...` 식으로 쓴다.
typeset -ga _CSM_UPD_ARGS
_csm_update_fzf_args() {
  _CSM_UPD_ARGS=()
  _csm_update_available || return
  local latest msg cols pad header
  latest=$(_csm_cached_latest)
  msg="업데이트 있음 ($latest) - U: 지금 업데이트"
  cols=${COLUMNS:-80}
  # zsh는 비-tty 환경에서 COLUMNS를 "0"으로 설정해두기도 해서(unset이 아님) ${:-} 폴백이
  # 안 먹는다 - 그 경우 우측정렬 대신 그냥 왼쪽 정렬로 조용히 성능 저하되는 걸 방지.
  [ "$cols" -le 0 ] 2>/dev/null && cols=80
  pad=$(( cols - ${#msg} ))
  (( pad < 0 )) && pad=0
  header=$(printf '%*s%s' "$pad" "" "$msg")
  _CSM_UPD_ARGS=(--header "$header" --bind "U:execute(zsh -ic 'csm --update')")
}

_csm_update() {
  local force=0
  case "$1" in
    --help|-h|-\?)
      cat <<'EOF'
사용법: csm --update [--force]

GitHub(orugu/csm)에서 최신 버전을 clone해서 install.sh를 다시 돌린다(재설치).
현재 버전보다 원격이 실제로 더 높을 때만 진행한다 - 이미 최신이거나(개발 중 버전처럼)
로컬이 더 앞서 있으면 그냥 알리고 끝낸다. 그래도 강제로 재설치하고 싶으면 --force.

설치 후에는 새 터미널을 열거나 'source ~/.zshrc' 해야 새 버전 함수가 적용된다
(현재 실행 중인 셸은 계속 옛날 버전의 함수를 갖고 있음 - 다른 CLI 업데이트와 동일).
EOF
      return
      ;;
    --force)
      force=1
      ;;
  esac

  echo "최신 버전 확인 중..."
  local remote remote_num
  remote=$(_csm_remote_version)
  if [ -z "$remote" ]; then
    echo "GitHub에서 버전 정보를 가져오지 못했습니다(네트워크 또는 저장소 접근 권한 확인)."
    return 1
  fi
  remote_num="${remote#v}"

  if [ "$force" -ne 1 ] && ! _csm_version_gt "$remote_num" "$_CSM_VERSION"; then
    if [ "$remote_num" = "$_CSM_VERSION" ]; then
      echo "이미 최신 버전입니다 ($_CSM_VERSION)."
    else
      echo "현재 버전($_CSM_VERSION)이 GitHub 최신 태그($remote)보다 같거나 앞서 있어서 아무것도 안 했습니다."
      echo "그래도 재설치하려면: csm --update --force"
    fi
    _csm_write_update_cache "$remote"
    return 0
  fi

  local tmpdir
  tmpdir=$(mktemp -d)
  echo "clone 중: $_CSM_REPO_SSH"
  if ! git clone --quiet --depth 1 "$_CSM_REPO_SSH" "$tmpdir" 2>/dev/null; then
    echo "저장소를 clone하지 못했습니다."
    rm -rf "$tmpdir"
    return 1
  fi

  bash "$tmpdir/install.sh"
  rm -rf "$tmpdir"
  _csm_write_update_cache "$remote"
  echo "업데이트 완료 ($remote). 새 터미널을 열거나 'source ~/.zshrc' 하세요."
}

sm() {
  _csm_update_fzf_args
  local host
  host=$(grep -E "^Host " ~/.ssh/config 2>/dev/null | grep -v '\*' | awk '{print $2}' | \
    fzf --height "$(_csm_fzf_height)%" --reverse --prompt="ssh > " \
        "${_CSM_UPD_ARGS[@]}" \
        --preview 'ssh -G {} | grep -E "^(hostname|user|port) " ')
  [ -n "$host" ] && ssh "$host"
}

_csm_help() {
  cat <<'EOF'
csm (Custom SSH Management) — fzf 기반 SSH 접속정보 관리/접속 도구

사용법:
  csm              그룹 -> 호스트 순으로 골라서 접속
  csm --mkdir      새 Host 항목을 대화형으로 추가
  csm --move       기존 호스트를 다른 그룹으로 이동
  csm --tunnel     호스트를 골라 SSH 포트포워딩(-L 로컬포워딩 / -D SOCKS) 열기
  csm --status     등록된 모든 호스트 생존/응답시간/uptime/디스크 사용량 확인
  csm --logs       여러 호스트를 멀티선택해서 로그를 동시에 tail
  csm --graph      ProxyJump 체인을 그룹별 트리로 시각화
  csm --copy-id    호스트를 골라 ssh-copy-id로 공개키 등록
  csm --setting    fzf UI로 각종 설정 값 변경
  csm --update     GitHub에서 최신 버전으로 재설치
  csm --help, -h   이 도움말
  sm               그룹 없이 전체 호스트를 flat하게 골라서 접속

그룹 분류는 ~/.ssh/config에 이렇게 주석을 달아서 관리한다:
  # csm-group: 그룹이름
  Host 별칭
      HostName ...

csm-group 주석이 하나도 없으면 csm은 sm과 동일하게 flat 목록으로 동작한다(정상 동작).
--mkdir/--move로 ~/.ssh/config를 고치기 전엔 항상 ~/.ssh/config.bak.<타임스탬프>로 백업한다.
EOF
}

_csm_backup_config() {
  cp ~/.ssh/config ~/.ssh/config.bak."$(date +%Y%m%d%H%M%S)"
}

# --- 설정 (csm --setting) -----------------------------------------------
# ~/.config/csm/settings.conf 에 KEY=VALUE 한 줄씩 저장. 파일이 없거나 키가
# 없으면 매번 넘겨준 기본값을 쓴다 - 매 호출마다 새로 읽으므로 csm --setting으로
# 바꾸면 같은 터미널에서 바로 다음 실행부터 반영된다(새 터미널/재로그인 불필요).
_CSM_SETTINGS_FILE="$HOME/.config/csm/settings.conf"

_csm_get_setting() {
  local key="$1" default="$2"
  if [ -f "$_CSM_SETTINGS_FILE" ]; then
    local val
    val=$(awk -F= -v k="$key" '$1==k{v=substr($0, index($0,"=")+1)} END{print v}' "$_CSM_SETTINGS_FILE")
    if [ -n "$val" ]; then
      echo "$val"
      return
    fi
  fi
  echo "$default"
}

_csm_set_setting() {
  local key="$1" val="$2"
  mkdir -p "$(dirname "$_CSM_SETTINGS_FILE")"
  touch "$_CSM_SETTINGS_FILE"
  local tmp
  tmp=$(mktemp)
  grep -v "^${key}=" "$_CSM_SETTINGS_FILE" > "$tmp" 2>/dev/null
  echo "${key}=${val}" >> "$tmp"
  mv "$tmp" "$_CSM_SETTINGS_FILE"
}

_csm_fzf_height() {
  _csm_get_setting fzf_height 40
}

_csm_setting() {
  case "$1" in
    --help|-h|-\?)
      cat <<'EOF'
사용법: csm --setting [--reset]

csm의 각종 동작을 fzf로 골라서 바꾼다. ~/.config/csm/settings.conf에 저장되고
바로 다음 실행부터 적용된다(새 터미널 필요 없음).

--reset  모든 설정을 지우고 기본값으로 되돌림

설정 항목:
  fzf_height          메뉴 높이(%). 기본 40
  status_timeout      csm --status의 호스트별 SSH 접속 타임아웃(초). 기본 5
  status_workers      csm --status 동시 접속 수. 기본 20
  mkdir_default_port  csm --mkdir에서 Port를 비워둘 때 자동으로 채울 기본값(비우면 미설정)
  logs_mode           csm --logs 방식: auto(tmux 있으면 자동 사용) / tmux / prefix. 기본 auto
  copy_id_key         csm --copy-id에서 자동판별 대신 항상 쓸 공개키 경로(비우면 자동판별)
EOF
      return
      ;;
    --reset)
      rm -f "$_CSM_SETTINGS_FILE"
      echo "설정을 초기화했습니다(전부 기본값)."
      return
      ;;
  esac

  while true; do
    local menu
    menu=$(cat <<EOF
fzf_height          (현재: $(_csm_get_setting fzf_height 40)%)
status_timeout      (현재: $(_csm_get_setting status_timeout 5)초)
status_workers      (현재: $(_csm_get_setting status_workers 20))
mkdir_default_port  (현재: $(_csm_get_setting mkdir_default_port "(미설정)"))
logs_mode           (현재: $(_csm_get_setting logs_mode auto))
copy_id_key         (현재: $(_csm_get_setting copy_id_key "(자동판별)"))
EOF
)
    local choice
    choice=$(printf '%s\n' "$menu" | \
      fzf --height "$(_csm_fzf_height)%" --reverse --prompt="설정 > " \
          --header="값 바꿀 항목을 고르세요 (Esc로 종료)")
    [ -z "$choice" ] && return

    local key="${choice%% *}"

    if [ "$key" = "logs_mode" ]; then
      local val
      val=$(printf 'auto\ntmux\nprefix\n' | \
        fzf --height "$(_csm_fzf_height)%" --reverse --prompt="logs_mode > ")
      [ -n "$val" ] && _csm_set_setting logs_mode "$val"
      continue
    fi

    printf "%s 새 값 (엔터만 누르면 취소): " "$key"
    local newval
    read -r newval
    [ -z "$newval" ] && continue

    # 숫자여야 하는 설정에 이상한 값을 넣으면 나중에 csm --status 등에서 파이썬
    # int() 변환이 그대로 터져서 크래시로 이어지던 버그가 있었다(실측 확인) - 저장 전에
    # 먼저 걸러낸다.
    case "$key" in
      status_timeout|status_workers|update_check_interval_hours|mkdir_default_port)
        if ! [[ "$newval" =~ ^[0-9]+$ ]] || [ "$newval" -le 0 ]; then
          echo "숫자(1 이상의 정수)만 가능합니다: $newval (저장 안 함)"
          continue
        fi
        ;;
      fzf_height)
        if ! [[ "$newval" =~ ^[0-9]+$ ]] || [ "$newval" -lt 1 ] || [ "$newval" -gt 100 ]; then
          echo "1~100 사이 숫자만 가능합니다: $newval (저장 안 함)"
          continue
        fi
        ;;
    esac

    _csm_set_setting "$key" "$newval"
  done
}

# ~/.ssh/config에서 그룹 이름만 등장 순서대로(중복 제거) 뽑기
_csm_list_groups() {
  awk '
    /^#[ \t]*csm-group:/ {
      sub(/^#[ \t]*csm-group:[ \t]*/, "")
      g = $0
      sub(/[ \t]+$/, "", g)
      if (!(g in seen)) { print g; seen[g] = 1 }
    }
  ' ~/.ssh/config
}

# 파일 내용이 실제로 유효한 SSH 공개키 한 줄 형식인지 검사(파일명이 .pub이어도
# 내용이 진짜 공개키인지는 열어봐야 알 수 있어서, 확장자만 보고 판단하지 않는다).
_csm_is_valid_pubkey() {
  [ -f "$1" ] || return 1
  head -c 40 "$1" 2>/dev/null | grep -qE \
    '^(ssh-rsa|ssh-ed25519|ssh-dss|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com) '
}

# ~/.ssh 안의 *.pub 파일 중 실제로 유효한 것만 한 줄씩 출력
_csm_find_pubkeys() {
  local f
  for f in ~/.ssh/*.pub(N); do
    _csm_is_valid_pubkey "$f" && echo "$f"
  done
}

# 호스트 하나를 받아서 적절한 공개키를 찾아 ssh-copy-id로 등록한다.
# 우선순위: 그 호스트에 IdentityFile이 지정돼 있으면 그 키 -> 없거나 못 찾으면
# ~/.ssh 안의 유효한 공개키 중에서 고르게 함(1개면 자동 선택, 여러 개면 fzf).
_csm_copy_id_for_host() {
  local host="$1"
  if ! command -v ssh-copy-id >/dev/null 2>&1; then
    echo "ssh-copy-id가 없습니다. (openssh 클라이언트 패키지 확인)"
    return 1
  fi

  local pubkey=""
  local forced_key
  forced_key=$(_csm_get_setting copy_id_key "")
  if [ -n "$forced_key" ]; then
    if _csm_is_valid_pubkey "$forced_key"; then
      pubkey="$forced_key"
    else
      echo "설정된 copy_id_key($forced_key)가 유효한 공개키가 아니라서 무시하고 자동판별합니다."
    fi
  fi

  local identity
  if [ -z "$pubkey" ]; then
    identity=$(ssh -G "$host" 2>/dev/null | awk '/^identityfile / {print $2; exit}')
    if [ -n "$identity" ]; then
      identity="${identity/#\~/$HOME}"
      if _csm_is_valid_pubkey "${identity}.pub"; then
        pubkey="${identity}.pub"
      fi
    fi
  fi

  if [ -z "$pubkey" ]; then
    local -a candidates
    candidates=("${(@f)$(_csm_find_pubkeys)}")
    if [ -z "${candidates[1]}" ]; then
      echo "~/.ssh 안에 쓸 수 있는 공개키(.pub)가 없습니다. ssh-keygen으로 먼저 키를 만드세요."
      return 1
    elif [ ${#candidates[@]} -eq 1 ]; then
      pubkey="${candidates[1]}"
    else
      pubkey=$(printf '%s\n' "${candidates[@]}" | fzf --height "$(_csm_fzf_height)%" --reverse --prompt="사용할 공개키 > ")
      [ -z "$pubkey" ] && return 1
    fi
  fi

  echo "등록할 키: $pubkey -> $host"
  ssh-copy-id -i "$pubkey" "$host"
}

_csm_copy_id() {
  case "$1" in
    --help|-h|-\?)
      cat <<'EOF'
사용법: csm --copy-id

호스트를 고른 뒤 ssh-copy-id로 공개키를 등록한다. 등록해두면 다음부터
비밀번호 없이 키로 바로 접속된다.

사용할 공개키는 이렇게 고른다:
  1) 그 호스트에 IdentityFile이 지정돼 있으면 그 키의 .pub을 우선 사용
  2) 아니면 ~/.ssh 안의 *.pub 파일 중 내용이 실제로 유효한 공개키 형식인 것만 후보로 삼음
     (파일명만 .pub이고 내용이 이상한 파일은 후보에서 제외)
  3) 후보가 1개면 자동 선택, 여러 개면 fzf로 고름
EOF
      return
      ;;
  esac

  if [ ! -f ~/.ssh/config ]; then
    echo "~/.ssh/config 가 없습니다."
    return 1
  fi

  local host
  host=$(grep -E "^Host " ~/.ssh/config | grep -v '\*' | awk '{print $2}' | \
    fzf --height "$(_csm_fzf_height)%" --reverse --prompt="키 등록할 호스트 > " \
        --preview 'ssh -G {} | grep -E "^(hostname|user|port|identityfile) " ')
  [ -z "$host" ] && return

  _csm_copy_id_for_host "$host"
}

_csm_mkdir() {
  if [ ! -f ~/.ssh/config ]; then
    echo "~/.ssh/config 가 없습니다. 먼저 만들어주세요."
    return 1
  fi

  local NEWGROUP_LABEL="[+ 새 그룹 만들기]"
  local group_choice
  group_choice=$( { _csm_list_groups; echo "$NEWGROUP_LABEL"; } | \
    fzf --height "$(_csm_fzf_height)%" --reverse --prompt="group > ")
  [ -z "$group_choice" ] && return

  local group is_new=0
  if [ "$group_choice" = "$NEWGROUP_LABEL" ]; then
    printf "새 그룹 이름: "
    read -r group
    if [ -z "$group" ]; then
      echo "취소됨"
      return 1
    fi
    is_new=1
  else
    group="$group_choice"
  fi

  printf "Host 별칭 (예: my-server): "
  local alias
  read -r alias
  if [ -z "$alias" ]; then
    echo "별칭은 필수입니다. 취소됨"
    return 1
  fi
  if grep -E "^Host " ~/.ssh/config | awk '{for(i=2;i<=NF;i++) print $i}' | grep -qxF "$alias"; then
    echo "이미 존재하는 별칭입니다: $alias (취소됨)"
    return 1
  fi

  printf "HostName (IP 또는 도메인, 엔터로 생략): "
  local hostname_val user_val port_val idfile_val
  read -r hostname_val
  printf "User (엔터로 생략): "
  read -r user_val
  local default_port
  default_port=$(_csm_get_setting mkdir_default_port "")
  # settings.conf 직접 편집으로 숫자가 아닌 값이 들어와 있으면 무시(빈 값 취급) -
  # 그대로 쓰면 ~/.ssh/config에 잘못된 Port 줄이 그대로 박혀버린다.
  if [ -n "$default_port" ] && ! [[ "$default_port" =~ ^[0-9]+$ ]]; then
    default_port=""
  fi
  printf "Port (엔터=%s): " "${default_port:-생략}"
  read -r port_val
  [ -z "$port_val" ] && port_val="$default_port"
  printf "IdentityFile 경로 (엔터로 생략): "
  read -r idfile_val

  local block="Host ${alias}
"
  [ -n "$hostname_val" ] && block="${block}    HostName ${hostname_val}
"
  [ -n "$user_val" ] && block="${block}    User ${user_val}
"
  [ -n "$port_val" ] && block="${block}    Port ${port_val}
"
  [ -n "$idfile_val" ] && block="${block}    IdentityFile ${idfile_val}
"
  block="${block}
"

  _csm_backup_config

  python3 - ~/.ssh/config "$group" "$is_new" "$block" <<'PYEOF'
import sys
path, group, new_group, block = sys.argv[1], sys.argv[2], sys.argv[3] == "1", sys.argv[4]

with open(path, encoding="utf-8") as f:
    lines = f.readlines()

if new_group:
    if lines and lines[-1].strip() != "":
        lines.append("\n")
    lines.append(f"# csm-group: {group}\n")
    lines.append(block)
else:
    target_idx = None
    for i, line in enumerate(lines):
        s = line.strip()
        if s.startswith("#") and "csm-group:" in s and s.split("csm-group:", 1)[1].strip() == group:
            target_idx = i
            break
    if target_idx is None:
        print("ERROR_GROUP_NOT_FOUND")
        sys.exit(1)
    lines[target_idx + 1:target_idx + 1] = [block]

with open(path, "w", encoding="utf-8") as f:
    f.writelines(lines)
print("OK")
PYEOF

  if [ $? -eq 0 ]; then
    echo "추가 완료: [$group] $alias"
    printf "지금 SSH 키를 등록할까요? (ssh-copy-id, 다음부터 비밀번호 없이 접속) [y/N]: "
    local do_copy_id
    read -r do_copy_id
    case "$do_copy_id" in
      y|Y|yes|YES) _csm_copy_id_for_host "$alias" ;;
    esac
  else
    echo "추가 실패 (백업은 남아있음: ~/.ssh/config.bak.*)"
  fi
}

_csm_move() {
  if [ ! -f ~/.ssh/config ]; then
    echo "~/.ssh/config 가 없습니다."
    return 1
  fi

  local alias
  alias=$(grep -E "^Host " ~/.ssh/config | grep -v '\*' | awk '{print $2}' | \
    fzf --height "$(_csm_fzf_height)%" --reverse --prompt="이동할 호스트 > ")
  [ -z "$alias" ] && return

  local NEWGROUP_LABEL="[+ 새 그룹 만들기]"
  local group_choice
  group_choice=$( { _csm_list_groups; echo "$NEWGROUP_LABEL"; } | \
    fzf --height "$(_csm_fzf_height)%" --reverse --prompt="옮길 그룹 > ")
  [ -z "$group_choice" ] && return

  local group is_new=0
  if [ "$group_choice" = "$NEWGROUP_LABEL" ]; then
    printf "새 그룹 이름: "
    read -r group
    if [ -z "$group" ]; then
      echo "취소됨"
      return 1
    fi
    is_new=1
  else
    group="$group_choice"
  fi

  _csm_backup_config

  python3 - ~/.ssh/config "$alias" "$group" "$is_new" <<'PYEOF'
import sys
path, alias, group, new_group = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"

def is_host_line(line):
    return line.lstrip().startswith("Host ")

def is_group_comment(line):
    s = line.strip()
    return s.startswith("#") and "csm-group:" in s

with open(path, encoding="utf-8") as f:
    lines = f.readlines()

block_start = None
for i, line in enumerate(lines):
    if is_host_line(line) and alias in line.split()[1:]:
        block_start = i
        break
if block_start is None:
    print("ERROR_HOST_NOT_FOUND")
    sys.exit(1)

block_end = len(lines)
for j in range(block_start + 1, len(lines)):
    if is_host_line(lines[j]) or is_group_comment(lines[j]):
        block_end = j
        break

block = lines[block_start:block_end]
del lines[block_start:block_end]

if new_group:
    if lines and lines[-1].strip() != "":
        lines.append("\n")
    lines.append(f"# csm-group: {group}\n")
    lines.extend(block)
else:
    target_idx = None
    for i, line in enumerate(lines):
        s = line.strip()
        if s.startswith("#") and "csm-group:" in s and s.split("csm-group:", 1)[1].strip() == group:
            target_idx = i
            break
    if target_idx is None:
        print("ERROR_GROUP_NOT_FOUND")
        sys.exit(1)
    lines[target_idx + 1:target_idx + 1] = block

with open(path, "w", encoding="utf-8") as f:
    f.writelines(lines)
print("OK")
PYEOF

  if [ $? -eq 0 ]; then
    echo "이동 완료: $alias -> [$group]"
  else
    echo "이동 실패 (백업: ~/.ssh/config.bak.*)"
  fi
}

_csm_tunnel() {
  case "$1" in
    --help|-h|-\?)
      cat <<'EOF'
사용법: csm --tunnel

호스트를 fzf로 고른 뒤 SSH 포트포워딩을 연다:
  - 로컬 포워딩(-L): 내 로컬 포트 -> (고른 호스트 경유) -> 지정한 원격 호스트:포트
  - SOCKS 동적 포워딩(-D): 내 로컬 포트를 SOCKS5 프록시로 사용 (브라우저 프록시 설정 등에 사용)

포그라운드로 실행되며 Ctrl+C로 터널을 닫는다.
EOF
      return
      ;;
  esac

  if [ ! -f ~/.ssh/config ]; then
    echo "~/.ssh/config 가 없습니다."
    return 1
  fi

  local host
  host=$(grep -E "^Host " ~/.ssh/config | grep -v '\*' | awk '{print $2}' | \
    fzf --height "$(_csm_fzf_height)%" --reverse --prompt="터널 열 호스트 > " \
        --preview 'ssh -G {} | grep -E "^(hostname|user|port) " ')
  [ -z "$host" ] && return

  local mode
  mode=$(printf '로컬 포워딩 (-L)\nSOCKS 동적 포워딩 (-D)\n' | \
    fzf --height "$(_csm_fzf_height)%" --reverse --prompt="포워딩 종류 > ")
  [ -z "$mode" ] && return

  if [[ "$mode" == SOCKS* ]]; then
    printf "로컬 포트 (SOCKS 프록시로 쓸 포트): "
    local local_port
    read -r local_port
    if [ -z "$local_port" ]; then
      echo "포트를 입력해야 합니다. 취소됨"
      return 1
    fi
    echo "SOCKS 프록시 여는 중: localhost:$local_port -> ($host 경유) (Ctrl+C로 종료)"
    ssh -N -D "$local_port" "$host"
  else
    printf "로컬 포트: "
    local local_port
    read -r local_port
    # $host를 printf 포맷 문자열에 직접 넣으면 호스트 별칭에 %가 있을 때 깨진다 -
    # %s로 인자를 분리해서 안전하게 넣는다.
    printf "원격 호스트 (엔터=localhost, %s 기준 상대적): " "$host"
    local remote_host
    read -r remote_host
    remote_host="${remote_host:-localhost}"
    printf "원격 포트: "
    local remote_port
    read -r remote_port
    if [ -z "$local_port" ] || [ -z "$remote_port" ]; then
      echo "로컬/원격 포트는 필수입니다. 취소됨"
      return 1
    fi
    # remote_host가 IPv6 리터럴(예: ::1, fe80::1)이면 콜론이 여러 개라
    # local:remote:port 구분자와 충돌한다 - ssh -L 문법대로 대괄호로 감싸야 한다.
    local remote_host_for_L="$remote_host"
    case "$remote_host" in
      *:*) [[ "$remote_host" == \[*\] ]] || remote_host_for_L="[${remote_host}]" ;;
    esac
    echo "터널 여는 중: localhost:$local_port -> ($host 경유) -> $remote_host:$remote_port (Ctrl+C로 종료)"
    ssh -N -L "${local_port}:${remote_host_for_L}:${remote_port}" "$host"
  fi
}

_csm_status() {
  case "$1" in
    --help|-h|-\?)
      cat <<'EOF'
사용법: csm --status

~/.ssh/config에 등록된 모든 호스트에 병렬로 SSH 접속해서
살아있는지 / 응답시간 / uptime / 디스크(/) 사용량을 표로 보여준다.

접속 실패한 호스트도 DOWN으로 같이 표시된다(오프라인, 방화벽, SSH 키 미등록 등).
SSH 키가 known_hosts에 없는 호스트는 비대화형(BatchMode)이라 자동으로 실패 처리된다
(중간자 공격 방지를 위해 자동으로 새 키를 신뢰하지 않음 — 처음 보는 호스트는
`ssh <host>`로 한 번 직접 접속해서 키를 등록해줘야 --status에서도 UP으로 잡힌다).
EOF
      return
      ;;
  esac

  if [ ! -f ~/.ssh/config ]; then
    echo "~/.ssh/config 가 없습니다."
    return 1
  fi

  local hosts
  hosts=$(grep -E "^Host " ~/.ssh/config | grep -v '\*' | awk '{for(i=2;i<=NF;i++) print $i}')
  if [ -z "$hosts" ]; then
    echo "등록된 호스트가 없습니다."
    return 1
  fi

  local timeout_setting workers_setting
  timeout_setting=$(_csm_get_setting status_timeout 5)
  workers_setting=$(_csm_get_setting status_workers 20)

  python3 - "$hosts" "$timeout_setting" "$workers_setting" <<'PYEOF'
import sys
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor

hosts = [h.strip() for h in sys.argv[1].splitlines() if h.strip()]


def _safe_int(raw, default, name):
    # settings.conf를 UI(csm --setting) 말고 텍스트 에디터로 직접 편집해서 숫자가
    # 아닌 값을 넣으면 예전엔 여기서 바로 크래시났다(실측 확인: status_timeout=abc).
    # UI 쪽 검증은 우회 가능하니 실제로 값을 쓰는 이 지점에서 방어한다.
    try:
        v = int(raw)
        if v <= 0:
            raise ValueError
        return v
    except (TypeError, ValueError):
        print(f"경고: {name} 설정값 {raw!r}이 올바르지 않아 기본값 {default}을 씁니다.", file=sys.stderr)
        return default


conn_timeout = _safe_int(sys.argv[2], 5, "status_timeout")
workers = _safe_int(sys.argv[3], 20, "status_workers")


def check(host):
    start = time.time()
    try:
        proc = subprocess.run(
            ["ssh", "-o", f"ConnectTimeout={conn_timeout}", "-o", "BatchMode=yes", host,
             "uptime; df -h / 2>/dev/null | tail -1"],
            capture_output=True, text=True, timeout=conn_timeout + 5,
        )
        elapsed = time.time() - start
        if proc.returncode != 0:
            err = proc.stderr.strip().splitlines()[-1] if proc.stderr.strip() else "접속 실패"
            return host, False, elapsed, err, ""
        lines = proc.stdout.strip().splitlines()
        uptime_line = lines[0] if lines else ""
        disk_line = lines[1] if len(lines) > 1 else ""
        return host, True, elapsed, uptime_line, disk_line
    except subprocess.TimeoutExpired:
        return host, False, time.time() - start, "타임아웃", ""
    except Exception as e:
        return host, False, time.time() - start, str(e), ""


results = []
with ThreadPoolExecutor(max_workers=workers) as ex:
    for r in ex.map(check, hosts):
        results.append(r)

print(f"{'Host':<24} {'상태':<6} {'응답시간':<10} Uptime / Disk")
print("-" * 100)
for host, ok, elapsed, info, disk in results:
    status = "UP" if ok else "DOWN"
    t = f"{elapsed:.2f}s"
    print(f"{host:<24} {status:<6} {t:<10} {info}")
    if ok and disk:
        print(f"{'':<24} {'':<6} {'':<10} {disk}")
PYEOF
}

_csm_logs() {
  case "$1" in
    --help|-h|-\?)
      cat <<'EOF'
사용법: csm --logs

fzf로 여러 호스트를 멀티선택(Tab으로 선택/해제, Enter로 확정)한 뒤, 각 호스트에서
돌릴 명령(예: "tail -f /var/log/syslog", "journalctl -f")을 입력하면 동시에 실행해서
로그를 한 화면에서 본다.

  - tmux가 있으면: 창을 호스트 수만큼 분할해서 각 창에 붙는다.
  - tmux가 없으면: 각 줄 앞에 [호스트명] 접두어를 붙여서 한 터미널에 섞어 보여준다
    (구분은 덜 되지만 tmux 설치 없이도 동작).

Ctrl+C로 전체 종료(tmux 쓰는 경우 tmux 세션 자체를 종료: prefix + &, 또는 세션 밖에서
`tmux kill-session -t <세션이름>`).
EOF
      return
      ;;
  esac

  if [ ! -f ~/.ssh/config ]; then
    echo "~/.ssh/config 가 없습니다."
    return 1
  fi

  local hosts_selected
  hosts_selected=$(grep -E "^Host " ~/.ssh/config | grep -v '\*' | awk '{print $2}' | \
    fzf --multi --height "$(_csm_fzf_height)%" --reverse --prompt="로그 볼 호스트(Tab으로 여러개, Enter로 확정) > " \
        --preview 'ssh -G {} | grep -E "^(hostname|user|port) " ')
  if [ -z "$hosts_selected" ]; then
    echo "선택 안 함"
    return
  fi

  printf "각 호스트에서 실행할 명령 (예: tail -f /var/log/syslog, journalctl -f): "
  local cmd
  read -r cmd
  if [ -z "$cmd" ]; then
    echo "명령을 입력해야 합니다. 취소됨"
    return 1
  fi

  # tmux 경로는 명령 전체를 하나의 문자열로 만들어서 tmux에 넘기는데, 그 문자열 안에서
  # $cmd를 그냥 작은따옴표로 감싸기만 하면(구버전 방식) $cmd 자체에 작은따옴표가 들어있을 때
  # (예: grep 'ERROR' 같은 명령) 그 따옴표가 감싸는 따옴표를 조기 종료시켜서 ssh에 명령이
  # 여러 조각으로 쪼개져 전달되는 버그가 있었다(실측 확인: sh -c로 재파싱해서 인자가
  # 2개로 쪼개지는 것까지 확인). zsh 내장 `${(q)var}`(셸이 다시 파싱해도 원래 문자열
  # 그대로 한 덩어리로 복원되는 자동 이스케이프)로 교체 - 수동 백슬래시 조합보다 훨씬 안전.
  local cmd_q="${(q)cmd}"

  local -a hosts_arr
  hosts_arr=("${(@f)hosts_selected}")

  local logs_mode
  logs_mode=$(_csm_get_setting logs_mode auto)
  local use_tmux=0
  if [ "$logs_mode" = "tmux" ]; then
    if command -v tmux >/dev/null 2>&1; then
      use_tmux=1
    else
      echo "설정(logs_mode=tmux)이 tmux를 쓰라고 돼있는데 tmux가 안 보입니다. 접두어 방식으로 대체합니다."
    fi
  elif [ "$logs_mode" != "prefix" ] && command -v tmux >/dev/null 2>&1; then
    use_tmux=1
  fi

  if [ "$use_tmux" -eq 1 ]; then
    local session="csm-logs-$$"
    tmux new-session -d -s "$session" -n logs "ssh ${hosts_arr[1]} $cmd_q; echo; echo '[${hosts_arr[1]} 종료됨, 아무 키나 누르면 창 닫힘]'; read -k1"
    local i
    for (( i = 2; i <= ${#hosts_arr[@]}; i++ )); do
      tmux split-window -t "$session" \
        "ssh ${hosts_arr[i]} $cmd_q; echo; echo '[${hosts_arr[i]} 종료됨, 아무 키나 누르면 창 닫힘]'; read -k1"
      tmux select-layout -t "$session" tiled > /dev/null
    done
    tmux attach -t "$session"
  else
    echo "tmux가 없어서 [호스트명] 접두어로 합쳐서 보여줍니다 (Ctrl+C로 전체 종료)."
    local -a pids
    local h h_esc
    for h in "${hosts_arr[@]}"; do
      # sed 치환 문자열에서 &는 "매치된 전체"를 뜻하는 특수문자라, 호스트 별칭에
      # &가 있으면 그 &만 조용히 사라져버린다(실측 확인) - 미리 \&로 이스케이프.
      h_esc="${h//&/\\&}"
      ssh "$h" "$cmd" 2>&1 | sed "s/^/[$h_esc] /" &
      pids+=($!)
    done
    trap "kill ${pids[@]} 2>/dev/null" INT
    wait
  fi
}

_csm_graph() {
  case "$1" in
    --help|-h|-\?)
      cat <<'EOF'
사용법: csm --graph

~/.ssh/config의 각 Host에 걸린 ProxyJump 관계를 그룹별 트리로 보여준다.
예: main -> parking -> HC1 처럼 여러 단계를 거쳐 접속하는 호스트 구조를 한눈에 파악.
ProxyJump가 없는 호스트는 트리의 뿌리(직접 접속)로 표시된다.
EOF
      return
      ;;
  esac

  if [ ! -f ~/.ssh/config ]; then
    echo "~/.ssh/config 가 없습니다."
    return 1
  fi

  python3 <<'PYEOF'
import os
import re

path = os.path.expanduser("~/.ssh/config")
with open(path, encoding="utf-8") as f:
    lines = f.readlines()

group = "기타"
group_order = []
# host -> {"group": ..., "proxyjump": ... or None}
hosts = {}

current_aliases = []


def flush(proxyjump):
    for a in current_aliases:
        hosts[a] = {"group": group, "proxyjump": proxyjump}


for line in lines:
    s = line.strip()
    m = re.match(r"#\s*csm-group:\s*(.+)$", s)
    if m:
        # 그룹을 바꾸기 전에 직전 Host 블록부터 확정해야 한다 — 안 그러면 ProxyJump 없는
        # 호스트(예: main)가 자기 그룹이 아니라 다음에 나오는 새 그룹으로 잘못 귀속된다
        # (실제로 이 파일 작성 중 논리를 추적하다 발견한 버그, 실행 전에 미리 수정함).
        flush(None)
        current_aliases = []
        group = m.group(1).strip()
        if group not in group_order:
            group_order.append(group)
        continue
    m = re.match(r"Host\s+(.+)$", s, re.IGNORECASE)
    if m:
        flush(None)  # 이전 Host 블록에 ProxyJump가 없었으면 확정
        aliases = [a for a in m.group(1).split() if "*" not in a]
        current_aliases = aliases
        continue
    m = re.match(r"ProxyJump\s+(.+)$", s, re.IGNORECASE)
    if m and current_aliases:
        flush(m.group(1).strip())
        current_aliases = []  # 이 블록은 이미 확정했으니 다음 Host 전까지 재확정 방지
flush(None)  # 마지막 블록 처리

for h in hosts.values():
    if h["group"] not in group_order:
        group_order.append(h["group"])

if not hosts:
    print("등록된 호스트가 없습니다.")
    raise SystemExit

children = {}
roots = []
for alias, info in hosts.items():
    jump = info["proxyjump"]
    if jump and jump in hosts:
        children.setdefault(jump, []).append(alias)
    else:
        roots.append((alias, jump))  # jump가 있는데 hosts에 없으면 외부 경유지로 표시


visited = set()


def print_tree(alias, prefix="", is_last=True, external_jump=None, _seen=None):
    # ProxyJump가 순환(A->B->A)이면 트리를 아무리 타고 내려가도 루트로 안 이어져서
    # 원래는 그 호스트들이 --graph 출력에서 통째로 조용히 사라지는 버그였다(실측 확인:
    # 2개짜리 순환을 만들어보니 두 호스트 다 roots에도 안 잡히고 출력 자체에서 빠짐).
    # 여기 _seen은 혹시 나중에 코드가 바뀌어서 사이클이 루트에서 도달 가능해지는
    # 경우에도 무한재귀로 죽지 않게 하는 이중 방어(현재 구조에선 발생 안 하지만 안전망).
    if _seen is None:
        _seen = set()
    if alias in _seen:
        print(prefix + "└── " + alias + "  (순환 참조 감지, 더 안 내려감)")
        return
    _seen = _seen | {alias}

    visited.add(alias)
    connector = "└── " if is_last else "├── "
    label = alias
    if external_jump:
        label += f"  (경유: {external_jump}, csm 목록 밖 호스트)"
    print(prefix + connector + label)
    child_prefix = prefix + ("    " if is_last else "│   ")
    kids = sorted(children.get(alias, []))
    for i, kid in enumerate(kids):
        print_tree(kid, child_prefix, i == len(kids) - 1, _seen=_seen)


for g in group_order:
    group_roots = sorted([a for a, j in roots if hosts[a]["group"] == g])
    if not group_roots:
        continue
    print(f"[{g}]")
    for i, alias in enumerate(group_roots):
        ext = next((j for a, j in roots if a == alias), None)
        print_tree(alias, "", i == len(group_roots) - 1, external_jump=ext)
    print()

unreachable = sorted(set(hosts) - visited)
if unreachable:
    print("[순환 참조로 도달 불가 - ProxyJump 설정을 확인하세요]")
    for alias in unreachable:
        print(f"  {alias}  (-> ProxyJump {hosts[alias]['proxyjump']})")
PYEOF
}

csm() {
  case "$1" in
    --help|-h|-\?)
      _csm_help
      return
      ;;
    --mkdir)
      _csm_mkdir
      return
      ;;
    --move)
      _csm_move
      return
      ;;
    --tunnel)
      shift
      _csm_tunnel "$@"
      return
      ;;
    --logs)
      shift
      _csm_logs "$@"
      return
      ;;
    --status)
      shift
      _csm_status "$@"
      return
      ;;
    --graph)
      shift
      _csm_graph "$@"
      return
      ;;
    --copy-id)
      shift
      _csm_copy_id "$@"
      return
      ;;
    --setting)
      shift
      _csm_setting "$@"
      return
      ;;
    --update)
      shift
      _csm_update "$@"
      return
      ;;
    -*)
      echo "알 수 없는 옵션: $1 (csm --help 참고)"
      return 1
      ;;
    "") ;;  # 인자 없음 - 정상, 아래 메뉴로 진행
    *)
      # 대시로 안 시작하는 인자를 조용히 무시하고 메뉴로 들어가던 버그(예: 오타로
      # `csm status`처럼 --를 빼먹으면 아무 말 없이 그냥 기본 메뉴가 뜸) - 안내하고 종료.
      echo "알 수 없는 인자: $1 (csm --help 참고)"
      return 1
      ;;
  esac

  if [ ! -f ~/.ssh/config ]; then
    echo "~/.ssh/config 가 없습니다."
    return 1
  fi

  local pairs
  pairs=$(awk '
    BEGIN { group="기타" }
    /^#[ \t]*csm-group:/ {
      sub(/^#[ \t]*csm-group:[ \t]*/, "")
      group = $0
      sub(/[ \t]+$/, "", group)
      next
    }
    /^Host[ \t]+/ {
      line = $0
      sub(/^Host[ \t]+/, "", line)
      n = split(line, hosts, /[ \t]+/)
      for (i = 1; i <= n; i++) {
        if (hosts[i] != "" && hosts[i] !~ /\*/) print group "\t" hosts[i]
      }
    }
  ' ~/.ssh/config)

  if [ -z "$pairs" ]; then
    sm
    return
  fi

  typeset -A groups
  typeset -a group_order
  local g h
  while IFS=$'\t' read -r g h; do
    if [ -z "${groups[$g]}" ]; then
      group_order+=("$g")
    fi
    groups[$g]="${groups[$g]} $h"
  done <<< "$pairs"

  if (( ${#group_order[@]} <= 1 )); then
    sm
    return
  fi

  _csm_update_fzf_args
  local group host
  while true; do
    group=$(printf '%s\n' "${group_order[@]}" | \
      fzf --height "$(_csm_fzf_height)%" --reverse --prompt="category > " \
          "${_CSM_UPD_ARGS[@]}")
    [ -z "$group" ] && return

    host=$(printf '%s\n' ${=groups[$group]} | \
      fzf --height "$(_csm_fzf_height)%" --reverse --prompt="$group > " \
          --bind 'backward-eof:abort' \
          "${_CSM_UPD_ARGS[@]}" \
          --preview 'ssh -G {} | grep -E "^(hostname|user|port) " ')

    if [ -n "$host" ]; then
      ssh "$host"
      return
    fi
    # backspace(빈 입력창에서)나 ESC로 취소한 경우 카테고리 메뉴로 복귀
  done
}
ZSHEOF

echo "설치됨: $TARGET_FILE"

# 3) .zshrc에 source 라인 추가 (이미 있으면 건너뜀 - 중복 방지)
SOURCE_LINE="[ -f \"$TARGET_FILE\" ] && source \"$TARGET_FILE\""

if [ -f "$ZSHRC" ] && grep -qF "$TARGET_FILE" "$ZSHRC" 2>/dev/null; then
  echo "$ZSHRC 에 이미 등록되어 있어서 건드리지 않았습니다."
else
  {
    echo ""
    echo "# sm/csm: fzf 기반 SSH 호스트 피커 (install-ssh-picker.sh로 설치됨)"
    echo "$SOURCE_LINE"
  } >> "$ZSHRC"
  echo "$ZSHRC 에 등록했습니다."
fi

echo
echo "완료. 새 터미널을 열거나 'source ~/.zshrc' 실행 후 sm / csm 명령을 쓸 수 있습니다."
echo "그룹 메뉴(csm)를 쓰려면 ~/.ssh/config에 아래처럼 주석을 추가하세요:"
echo "  # csm-group: 그룹이름"
echo "  Host 호스트별칭"
