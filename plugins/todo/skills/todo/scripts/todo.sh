#!/usr/bin/env bash
# todo.sh — 프로젝트 로컬 할 일 목록(.claude/todo/todo.md) 헬퍼.
#
# 설계 의도: todo.md 전문을 읽지 않고도 항목을 추가/조회/완료할 수 있게 한다.
# 그래서 list 는 제목만, show 는 지정한 항목만 출력하고, done 은 해당 블록만
# 잘라내 backup/ 으로 옮긴다.
set -eu

SELF="$(basename "$0")"

usage() {
  cat <<'EOF'
todo.sh — .claude/todo/todo.md 를 다루는 헬퍼

사용법:
  todo.sh [--dir <경로>] <서브커맨드> [인자...]

서브커맨드:
  init                          .claude/todo/ 와 todo.md 를 만든다 (있으면 그대로 둔다)
  add --title "제목" [--body "본문"]
                                항목을 추가하고 새 ID 를 출력한다.
                                --body - 로 주면 본문을 표준 입력에서 읽는다.
                                --body 를 아예 생략하면 상세 없는 항목이 된다.
  edit <ID> [--title "새 제목"] [--body "본문"] [--append "덧붙일 줄"] [--clear-body]
                                기존 항목을 제자리에서 고친다 (ID 는 그대로 유지).
                                --title 만 주면 상세는 그대로, --body 는 상세를 통째로
                                교체, --append 는 상세 끝에 덧붙인다.
                                --body / --append 도 - 로 주면 표준 입력에서 읽는다.
  list                          ID 와 제목만 나열한다 (상세는 출력하지 않는다)
  show <ID>...                  지정한 항목의 제목과 상세를 출력한다
  find <검색어>                 제목에 검색어가 들어간 항목의 ID/제목을 출력한다
  done <ID>... [--note "메모"]  항목을 todo.md 에서 빼고 backup/ 에 완료로 보관한다
  cancel <ID>... [--note "메모"] 항목을 todo.md 에서 빼고 backup/ 에 취소로 보관한다
  log                           backup/ 에 보관된 항목의 파일명을 나열한다
  path                          todo.md / backup 경로를 출력한다

옵션:
  --dir <경로>    todo 디렉터리 직접 지정 (기본: <git 루트>/.claude/todo)
  -h, --help      이 도움말

ID 는 T7 처럼 쓰거나 숫자만(7) 써도 된다.
EOF
}

die() { printf '%s: %s\n' "$SELF" "$1" >&2; exit 1; }

# --- 경로 결정 -------------------------------------------------------------

DIR_OPT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) [ $# -ge 2 ] || die "--dir 에 경로가 필요합니다"; DIR_OPT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) break ;;
  esac
done

if [ -n "$DIR_OPT" ]; then
  TODO_DIR="$DIR_OPT"
elif [ -n "${CLAUDE_TODO_DIR:-}" ]; then
  TODO_DIR="$CLAUDE_TODO_DIR"
else
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  TODO_DIR="$ROOT/.claude/todo"
fi

TODO_FILE="$TODO_DIR/todo.md"
BACKUP_DIR="$TODO_DIR/backup"
SEQ_FILE="$TODO_DIR/.seq"
TODAY="$(date +%F)"

ensure_file() {
  mkdir -p "$TODO_DIR"
  if [ ! -f "$TODO_FILE" ]; then
    cat > "$TODO_FILE" <<'EOF'
# TODO

<!-- todo 스킬이 관리하는 파일입니다. scripts/todo.sh 로 편집하세요. -->
<!-- 형식: `- [ ] (T1) 제목` 한 줄 + 들여쓴 상세 줄들 -->

EOF
  fi
}

# 파일 끝이 개행으로 끝나도록 보정 (append 가 이전 줄에 붙는 사고 방지)
ensure_trailing_newline() {
  [ -s "$TODO_FILE" ] || return 0
  if [ -n "$(tail -c 1 "$TODO_FILE")" ]; then printf '\n' >> "$TODO_FILE"; fi
}

# --- ID 관리 ---------------------------------------------------------------

scan_ids() {
  if [ -f "$TODO_FILE" ]; then
    grep -o '^- \[[ xX]\] (T[0-9][0-9]*)' "$TODO_FILE" 2>/dev/null \
      | grep -o '[0-9][0-9]*' || true
  fi
  if [ -d "$BACKUP_DIR" ]; then
    ls -1 "$BACKUP_DIR" 2>/dev/null | grep -o '^T[0-9][0-9]*' | sed 's/^T//' || true
  fi
}

# 다음 ID. .seq 를 신뢰하되, 유실/되돌림에 대비해 실제 파일들의 최대값과도 비교한다.
next_id() {
  cur=0
  if [ -f "$SEQ_FILE" ]; then
    cur="$(tr -cd '0-9' < "$SEQ_FILE")"
    [ -n "$cur" ] || cur=0
  fi
  for n in $(scan_ids); do
    [ "$n" -gt "$cur" ] && cur="$n"
  done
  cur=$((cur + 1))
  printf '%s' "$cur" > "$SEQ_FILE"
  printf 'T%s' "$cur"
}

normalize_id() {
  case "$1" in
    T[0-9]*|t[0-9]*) printf 'T%s' "${1#[Tt]}" ;;
    [0-9]*) printf 'T%s' "$1" ;;
    *) die "ID 형식이 아닙니다: $1 (T7 또는 7)" ;;
  esac
}

# --- 블록 조작 -------------------------------------------------------------
# 항목 블록 = `- [ ] (T7) 제목` 줄 + 뒤따르는 들여쓴 줄들.

extract_block() {
  awk -v target="$1" '
    {
      if (match($0, /^- \[[ xX]\] \(T[0-9]+\)/)) {
        head = substr($0, 1, RLENGTH)
        match(head, /T[0-9]+/)
        inblk = (substr(head, RSTART, RLENGTH) == target)
      } else if ($0 !~ /^[ \t]+[^ \t]/) {
        inblk = 0
      }
      if (inblk) print
    }
  ' "$TODO_FILE"
}

# 항목 블록을 파일 안 같은 자리에서 새 내용(파일)으로 갈아끼운다.
replace_block() {
  awk -v target="$1" -v newfile="$2" '
    function emit(  line) {
      while ((getline line < newfile) > 0) print line
      close(newfile)
    }
    {
      if (match($0, /^- \[[ xX]\] \(T[0-9]+\)/)) {
        head = substr($0, 1, RLENGTH)
        match(head, /T[0-9]+/)
        skip = (substr(head, RSTART, RLENGTH) == target)
        if (skip) { emit(); next }
      } else if ($0 !~ /^[ \t]+[^ \t]/) {
        skip = 0
      }
      if (!skip) print
    }
  ' "$TODO_FILE" > "$TODO_FILE.tmp"
  mv "$TODO_FILE.tmp" "$TODO_FILE"
}

remove_block() {
  awk -v target="$1" '
    {
      if (match($0, /^- \[[ xX]\] \(T[0-9]+\)/)) {
        head = substr($0, 1, RLENGTH)
        match(head, /T[0-9]+/)
        skip = (substr(head, RSTART, RLENGTH) == target)
      } else if ($0 !~ /^[ \t]+[^ \t]/) {
        skip = 0
      }
      if (!skip) print
    }
  ' "$TODO_FILE" > "$TODO_FILE.tmp"
  mv "$TODO_FILE.tmp" "$TODO_FILE"
}

strip_title() {
  # `- [ ] (T7) 제목 <!-- added:... -->` → `제목`
  printf '%s' "$1" \
    | sed -e 's/^- \[[ xX]\] ([Tt][0-9]*)[[:space:]]*//' \
          -e 's/[[:space:]]*<!--.*-->[[:space:]]*$//' \
          -e 's/[[:space:]]*$//'
}

# 제목 줄 끝 주석에서 added: / edited: 날짜를 뽑는다 (없으면 빈 문자열)
meta_field() {
  printf '%s' "$1" | sed -n "s/.*<!--[^>]*$2:\([0-9][0-9-]*\).*-->.*/\1/p"
}

# 상세를 todo.md 에 넣을 형태로 정규화:
# 빈 줄 제거(리스트가 loose 해지는 것 방지) + 2칸 들여쓰기로 항목에 종속시킴
indent_body() {
  printf '%s\n' "$1" \
    | sed -e 's/\r$//' -e 's/[[:space:]]*$//' -e '/^$/d' -e 's/^/  /'
}

# --- 서브커맨드 ------------------------------------------------------------

cmd_init() {
  ensure_file
  mkdir -p "$BACKUP_DIR"
  printf '%s\n' "$TODO_FILE"
}

cmd_add() {
  title=""; body=""; from_stdin=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --title) [ $# -ge 2 ] || die "--title 에 값이 필요합니다"; title="$2"; shift 2 ;;
      --body)  [ $# -ge 2 ] || die "--body 에 값이 필요합니다"
               if [ "$2" = "-" ]; then from_stdin=1; else body="$2"; fi
               shift 2 ;;
      *) die "알 수 없는 인자: $1" ;;
    esac
  done
  [ -n "$title" ] || die "--title 이 필요합니다"
  case "$title" in *$'\n'*) die "제목은 한 줄이어야 합니다 (여러 줄은 --body 로)" ;; esac

  ensure_file
  ensure_trailing_newline
  # stdin 은 명시적으로 요청했을 때만 읽는다. 자동 감지는 tty 가 없는 환경에서
  # 입력을 기다리며 멎어버리기 때문에 쓰지 않는다.
  if [ "$from_stdin" -eq 1 ]; then body="$(cat)"; fi

  id="$(next_id)"
  printf -- '- [ ] (%s) %s <!-- added:%s -->\n' "$id" "$title" "$TODAY" >> "$TODO_FILE"
  if [ -n "$body" ]; then
    indent_body "$body" >> "$TODO_FILE"
  fi
  printf '%s\n' "$id"
}

cmd_edit() {
  [ $# -ge 1 ] || die "edit 에는 ID 가 필요합니다"
  case "$1" in -*) die "edit 의 첫 인자는 ID 여야 합니다 (예: edit T7 --title \"...\")" ;; esac
  id="$(normalize_id "$1")"; shift

  set_title=0; new_title=""
  set_body=0;  new_body="";    body_stdin=0
  do_append=0; append_text=""; append_stdin=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --title) [ $# -ge 2 ] || die "--title 에 값이 필요합니다"
               set_title=1; new_title="$2"; shift 2 ;;
      --body)  [ $# -ge 2 ] || die "--body 에 값이 필요합니다"
               set_body=1
               if [ "$2" = "-" ]; then body_stdin=1; else new_body="$2"; fi
               shift 2 ;;
      --append) [ $# -ge 2 ] || die "--append 에 값이 필요합니다"
               do_append=1
               if [ "$2" = "-" ]; then append_stdin=1; else append_text="$2"; fi
               shift 2 ;;
      --clear-body) set_body=1; new_body=""; shift ;;
      *) die "알 수 없는 인자: $1" ;;
    esac
  done

  if [ $((set_title + set_body + do_append)) -eq 0 ]; then
    die "고칠 내용이 없습니다 (--title / --body / --append / --clear-body 중 하나 이상 필요)"
  fi
  [ $((body_stdin + append_stdin)) -le 1 ] || die "--body - 와 --append - 는 함께 쓸 수 없습니다 (표준 입력은 하나뿐)"

  ensure_file
  block="$(extract_block "$id")"
  [ -n "$block" ] || die "$id 항목을 찾을 수 없습니다 (list 로 확인하세요)"

  head_line="$(printf '%s\n' "$block" | head -n 1)"
  old_body="$(printf '%s\n' "$block" | tail -n +2 | sed 's/^  //')"
  added="$(meta_field "$head_line" added)"
  case "$head_line" in
    '- [x]'*|'- [X]'*) box="x" ;;
    *) box=" " ;;
  esac

  if [ "$set_title" -eq 1 ]; then
    title="$new_title"
  else
    title="$(strip_title "$head_line")"
  fi
  [ -n "$title" ] || die "제목이 비었습니다"
  case "$title" in *$'\n'*) die "제목은 한 줄이어야 합니다 (여러 줄은 --body 로)" ;; esac

  # stdin 은 명시적으로 - 를 줬을 때만 읽는다 (add 와 같은 이유).
  if [ "$body_stdin" -eq 1 ]; then new_body="$(cat)"; fi
  if [ "$append_stdin" -eq 1 ]; then append_text="$(cat)"; fi

  if [ "$set_body" -eq 1 ]; then body="$new_body"; else body="$old_body"; fi
  if [ "$do_append" -eq 1 ]; then
    if [ -n "$body" ]; then
      body="$body
$append_text"
    else
      body="$append_text"
    fi
  fi

  meta="edited:$TODAY"
  if [ -n "$added" ]; then meta="added:$added $meta"; fi

  tmp="$TODO_DIR/.edit.$$"
  {
    printf -- '- [%s] (%s) %s <!-- %s -->\n' "$box" "$id" "$title" "$meta"
    if [ -n "$body" ]; then indent_body "$body"; fi
  } > "$tmp"
  replace_block "$id" "$tmp"
  rm -f "$tmp"

  printf '%s 수정됨:\n' "$id"
  extract_block "$id"
}

cmd_list() {
  ensure_file
  out="$(awk '
    function flush() {
      if (id != "") {
        printf "%-5s %s%s%s\n", id, mark, title, (n > 0 ? "  (상세 " n "줄)" : "")
      }
      id = ""; title = ""; mark = ""; n = 0
    }
    {
      if (match($0, /^- \[[ xX]\] \(T[0-9]+\)[ \t]/)) {
        flush()
        hl = RLENGTH            # 아래 match() 가 RLENGTH 를 덮어쓰므로 먼저 보관
        head = substr($0, 1, hl)
        match(head, /T[0-9]+/)
        id = substr(head, RSTART, RLENGTH)
        mark = (head ~ /\[[xX]\]/) ? "[완료표시] " : ""
        title = substr($0, hl + 1)
        sub(/[ \t]*<!--.*-->[ \t]*$/, "", title)
        sub(/[ \t]+$/, "", title)
        next
      }
      if (id != "" && $0 ~ /^[ \t]+[^ \t]/) { n++; next }
      if ($0 !~ /^[ \t]*$/) flush()
    }
    END { flush() }
  ' "$TODO_FILE")"

  if [ -z "$out" ]; then
    printf '할 일이 없습니다. (%s)\n' "$TODO_FILE"
  else
    printf '%s\n' "$out"
  fi
}

cmd_show() {
  [ $# -gt 0 ] || die "show 에는 ID 가 필요합니다"
  ensure_file
  first=1
  for raw in "$@"; do
    id="$(normalize_id "$raw")"
    block="$(extract_block "$id")"
    [ -n "$block" ] || die "$id 항목을 찾을 수 없습니다 (list 로 확인하세요)"
    [ "$first" -eq 1 ] || printf '\n'
    first=0
    printf '%s\n' "$block"
  done
}

cmd_find() {
  [ $# -ge 1 ] || die "find 에는 검색어가 필요합니다"
  ensure_file
  out="$(awk -v q="$1" '
    BEGIN { ql = tolower(q) }
    match($0, /^- \[[ xX]\] \(T[0-9]+\)[ \t]/) {
      hl = RLENGTH             # 아래 match() 가 RLENGTH 를 덮어쓴다
      head = substr($0, 1, hl)
      match(head, /T[0-9]+/)
      id = substr(head, RSTART, RLENGTH)
      title = substr($0, hl + 1)
      sub(/[ \t]*<!--.*-->[ \t]*$/, "", title)
      sub(/[ \t]+$/, "", title)
      if (index(tolower(title), ql) > 0) printf "%-5s %s\n", id, title
    }
  ' "$TODO_FILE")"

  if [ -z "$out" ]; then
    printf '"%s" 와 제목이 겹치는 항목이 없습니다.\n' "$1"
    exit 1
  fi
  printf '%s\n' "$out"
}

yaml_str() {
  printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
}

slugify() {
  s="$(printf '%s' "$1" \
    | sed -e 's/[\/\\:*?"<>|]//g' \
          -e 's/[[:space:]][[:space:]]*/-/g' \
          -e 's/^-*//' -e 's/-*$//')"
  s="$(printf '%s' "$s" | cut -c1-60)"
  [ -n "$s" ] || s="untitled"
  printf '%s' "$s"
}

# done / cancel 공통 처리
cmd_close() {
  status="$1"; shift
  note=""
  set -- "$@"
  ids=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --note) [ $# -ge 2 ] || die "--note 에 값이 필요합니다"; note="$2"; shift 2 ;;
      -*) die "알 수 없는 옵션: $1" ;;
      *) ids="$ids $1"; shift ;;
    esac
  done
  [ -n "$ids" ] || die "$status 처리할 ID 가 필요합니다"

  ensure_file
  mkdir -p "$BACKUP_DIR"

  case "$status" in
    done)   status_label="완료"; status_field="done" ;;
    cancel) status_label="취소"; status_field="cancelled" ;;
    *) die "알 수 없는 상태: $status" ;;
  esac

  for raw in $ids; do
    id="$(normalize_id "$raw")"
    block="$(extract_block "$id")"
    [ -n "$block" ] || die "$id 항목을 찾을 수 없습니다 (list 로 확인하세요)"

    head_line="$(printf '%s\n' "$block" | head -n 1)"
    title="$(strip_title "$head_line")"
    added="$(meta_field "$head_line" added)"
    [ -n "$added" ] || added="unknown"
    edited="$(meta_field "$head_line" edited)"
    body="$(printf '%s\n' "$block" | tail -n +2 | sed 's/^  //')"

    out="$BACKUP_DIR/$id-$(slugify "$title").md"
    if [ -e "$out" ]; then
      i=2
      while [ -e "$BACKUP_DIR/$id-$(slugify "$title")-$i.md" ]; do i=$((i + 1)); done
      out="$BACKUP_DIR/$id-$(slugify "$title")-$i.md"
    fi

    {
      printf -- '---\n'
      printf 'id: %s\n' "$id"
      printf 'title: %s\n' "$(yaml_str "$title")"
      printf 'status: %s\n' "$status_field"
      printf 'added: %s\n' "$added"
      if [ -n "$edited" ]; then printf 'edited: %s\n' "$edited"; fi
      printf 'closed: %s\n' "$TODAY"
      printf -- '---\n\n'
      printf '# %s\n' "$title"
      if [ -n "$body" ]; then printf '\n%s\n' "$body"; fi
      if [ -n "$note" ]; then printf '\n## %s 메모\n\n%s\n' "$status_label" "$note"; fi
    } > "$out"

    remove_block "$id"
    printf '%s %s → %s\n' "$id" "$status_label" "$out"
  done
}

cmd_log() {
  if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
    printf '보관된 항목이 없습니다. (%s)\n' "$BACKUP_DIR"
    return 0
  fi
  ls -1 "$BACKUP_DIR"
}

cmd_path() {
  printf 'todo:   %s\n' "$TODO_FILE"
  printf 'backup: %s\n' "$BACKUP_DIR"
}

# --- 디스패치 --------------------------------------------------------------

[ $# -gt 0 ] || { usage; exit 1; }
sub="$1"; shift

case "$sub" in
  init)   cmd_init "$@" ;;
  add)    cmd_add "$@" ;;
  edit)   cmd_edit "$@" ;;
  list)   cmd_list "$@" ;;
  show)   cmd_show "$@" ;;
  find)   cmd_find "$@" ;;
  done)   cmd_close done "$@" ;;
  cancel) cmd_close cancel "$@" ;;
  log)    cmd_log "$@" ;;
  path)   cmd_path "$@" ;;
  help|-h|--help) usage ;;
  *) die "알 수 없는 서브커맨드: $sub (--help 참고)" ;;
esac
