#!/usr/bin/env bash
# sm / csm (Custom SSH Management, fzf 기반 SSH 접속정보 관리/접속 도구) 설치 스크립트.
# version 1.2 (2026-07-30)
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

sm() {
  local host
  host=$(grep -E "^Host " ~/.ssh/config 2>/dev/null | grep -v '\*' | awk '{print $2}' | \
    fzf --height 40% --reverse --prompt="ssh > " \
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

_csm_mkdir() {
  if [ ! -f ~/.ssh/config ]; then
    echo "~/.ssh/config 가 없습니다. 먼저 만들어주세요."
    return 1
  fi

  local NEWGROUP_LABEL="[+ 새 그룹 만들기]"
  local group_choice
  group_choice=$( { _csm_list_groups; echo "$NEWGROUP_LABEL"; } | \
    fzf --height 40% --reverse --prompt="group > ")
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
  printf "Port (엔터로 생략, 기본 22): "
  read -r port_val
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
    fzf --height 40% --reverse --prompt="이동할 호스트 > ")
  [ -z "$alias" ] && return

  local NEWGROUP_LABEL="[+ 새 그룹 만들기]"
  local group_choice
  group_choice=$( { _csm_list_groups; echo "$NEWGROUP_LABEL"; } | \
    fzf --height 40% --reverse --prompt="옮길 그룹 > ")
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
    fzf --height 40% --reverse --prompt="터널 열 호스트 > " \
        --preview 'ssh -G {} | grep -E "^(hostname|user|port) " ')
  [ -z "$host" ] && return

  local mode
  mode=$(printf '로컬 포워딩 (-L)\nSOCKS 동적 포워딩 (-D)\n' | \
    fzf --height 40% --reverse --prompt="포워딩 종류 > ")
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
    printf "원격 호스트 (엔터=localhost, $host 기준 상대적): "
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
    echo "터널 여는 중: localhost:$local_port -> ($host 경유) -> $remote_host:$remote_port (Ctrl+C로 종료)"
    ssh -N -L "${local_port}:${remote_host}:${remote_port}" "$host"
  fi
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
    -*)
      echo "알 수 없는 옵션: $1 (csm --help 참고)"
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

  local group host
  while true; do
    group=$(printf '%s\n' "${group_order[@]}" | \
      fzf --height 40% --reverse --prompt="category > ")
    [ -z "$group" ] && return

    host=$(printf '%s\n' ${=groups[$group]} | \
      fzf --height 40% --reverse --prompt="$group > " \
          --bind 'backward-eof:abort' \
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
