#!/bin/bash
# Claude Code status line
#   1줄: 모델 | git 브랜치(worktree, dirty 상태) | 현재 시간
#   2줄: Context 게이지 (컨텍스트 윈도우 사용률)
#   3줄: Usage 게이지 (5시간 rate limit 사용률 + 리셋 시각)
# JSON 파싱: jq 우선, 없으면 PowerShell 폴백 (Windows)
# 워크트리별 색 네모: statusline-worktree-colors 설정 파일 참조 (/statusline:color 로 지정)
input=$(cat)
now=$(date +%H:%M:%S)

# 필드 구분자: ASCII unit separator (경로 등 값에 섞일 수 없는 문자)
US=$'\x1f'

# 직전 정상 파싱값 캐시 (pwsh 지연/중단 등으로 이번 파싱이 실패하면 이 값으로 폴백)
CACHE_FILE="$HOME/.claude/.statusline-cache"

# pwsh가 멈춰 렌더 전체를 물고 늘어지지 않도록 상한 (있으면 사용)
pwsh_guard=""
if command -v timeout &>/dev/null; then
    pwsh_guard="timeout 4"
fi

parsed=""
if command -v jq &>/dev/null; then
    parsed=$(printf '%s' "$input" | jq -r '
        [
            (.model.display_name // ""),
            (.cwd // ""),
            (if .context_window.used_percentage != null then (.context_window.used_percentage | round | tostring) else "" end),
            (if .rate_limits.five_hour != null then (.rate_limits.five_hour.used_percentage | round | tostring) else "" end),
            (if .rate_limits.five_hour != null then (.rate_limits.five_hour.resets_at | tostring) else "" end)
        ] | join("\u001f")
    ' 2>/dev/null)
else
    ps_script='
        $d = $input | ConvertFrom-Json -ErrorAction SilentlyContinue
        $model = ""; $cwd = ""; $ctx = ""; $rate = ""; $reset = ""
        if ($d) {
            if ($d.model -and $d.model.display_name) { $model = $d.model.display_name }
            if ($d.cwd) { $cwd = $d.cwd }
            if ($d.context_window -and $null -ne $d.context_window.used_percentage) { $ctx = [math]::Round($d.context_window.used_percentage) }
            if ($d.rate_limits -and $d.rate_limits.five_hour) {
                $rate = [math]::Round($d.rate_limits.five_hour.used_percentage)
                $reset = $d.rate_limits.five_hour.resets_at
            }
        }
        $us = [char]0x1f
        "$model$us$cwd$us$ctx$us$rate$us$reset"
    '
    if command -v pwsh &>/dev/null; then
        parsed=$(printf '%s' "$input" | $pwsh_guard pwsh -NoProfile -NonInteractive -Command "$ps_script" 2>/dev/null)
    elif command -v powershell &>/dev/null; then
        parsed=$(printf '%s' "$input" | $pwsh_guard powershell -NoProfile -NonInteractive -Command "$ps_script" 2>/dev/null)
    fi
fi

parsed=$(printf '%s' "$parsed" | tr -d '\r\n')
IFS="$US" read -r model cwd used rate_used reset_epoch <<< "$parsed"

# git 브랜치/워크트리는 반드시 "실제 현재 디렉터리" 기준으로만 계산한다.
# cwd는 절대 캐시에 넣지 않는다 — 넣으면 다른 세션/워크트리에서 저장한 cwd가
# 흘러들어와 엉뚱한 워크트리·브랜치·레포가 표시된다(전역 캐시는 모든 워크트리 공유).
# 파싱값이 있으면 그걸, 없으면(파싱 실패) 이 프로세스의 실제 cwd를 쓴다.
cwd="${cwd:-$PWD}"

# model/context/usage 만 캐시로 폴백한다(이들은 JSON 외 다른 소스가 없음).
# 파싱 성공(model 존재) → 캐시 갱신 / 실패 → 직전 정상값. status line은 주기적으로
# 재호출되므로 다음 렌더에서 파싱이 회복되면 캐시가 자동 갱신된다(= 사실상의 재시도).
if [ -n "$model" ]; then
    printf '%s\037%s\037%s\037%s' "$model" "$used" "$rate_used" "$reset_epoch" > "$CACHE_FILE" 2>/dev/null
elif [ -f "$CACHE_FILE" ]; then
    IFS="$US" read -r model used rate_used reset_epoch <<< "$(cat "$CACHE_FILE" 2>/dev/null)"
fi

# 리셋 시각: epoch → HH:mm (GNU date는 -d @, BSD/macOS date는 -r)
rate_reset=""
if [ -n "$reset_epoch" ]; then
    rate_reset=$(date -d "@$reset_epoch" +%H:%M 2>/dev/null || date -r "$reset_epoch" +%H:%M 2>/dev/null)
fi

# ─────────────────────────────────────────────────────────────────────────────
# 워크트리 색상 설정 (statusline-worktree-colors)
#   포맷: 워크트리폴더명=색   (# 주석 / 빈 줄 무시, 키는 대소문자 무시)
#   색  : #RRGGBB | #RGB | R;G;B | 프리셋 이름
#   조회: <메인 체크아웃>/.claude/... 우선, 없는 키는 ~/.claude/... 로 폴백(키 단위 병합)
#   잘못된 값은 조용히 무시한다 — status line에 에러가 새어나오면 안 된다.
# ─────────────────────────────────────────────────────────────────────────────
COLOR_FILE_NAME="statusline-worktree-colors"

# 설정 파일에서 키에 해당하는 값 1개를 출력. 못 찾으면 non-zero.
# 외부 프로세스(grep/sed)를 쓰지 않는다 — 렌더마다 호출되므로.
lookup_color() {
    local name="$1" file="$2" line key val
    [ -f "$file" ] || return 1
    name="${name,,}"
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"                       # CRLF 대응
        case "$line" in ''|'#'*) continue ;; esac
        case "$line" in *'='*) ;; *) continue ;; esac
        key="${line%%=*}"
        val="${line#*=}"
        key="${key#"${key%%[![:space:]]*}"}"       # 앞뒤 공백 제거
        key="${key%"${key##*[![:space:]]}"}"
        val="${val#"${val%%[![:space:]]*}"}"
        val="${val%"${val##*[![:space:]]}"}"
        if [ "${key,,}" = "$name" ] && [ -n "$val" ]; then
            printf '%s' "$val"
            return 0
        fi
    done < "$file"
    return 1
}

# 색 값을 ANSI용 "R;G;B" 로 정규화. 해석 불가면 non-zero.
resolve_rgb() {
    local v="$1" h r g b
    # 프리셋은 "작은 네모 하나로 구분" 이 목적이라 색상환을 넓게 벌린 고채도 색을 쓴다.
    # (게이지/브랜치명의 파스텔 팔레트와 일부러 다르게 간다)
    case "${v,,}" in
        red)             v="#FF2D2D" ;;
        orange|peach)    v="#FF8A00" ;;
        yellow)          v="#FFD400" ;;
        lime)            v="#9EFF00" ;;
        green)           v="#00E05A" ;;
        teal)            v="#00E0C0" ;;
        cyan|sky)        v="#00D5FF" ;;
        blue)            v="#2E7BFF" ;;
        purple|mauve)    v="#9B5CFF" ;;
        magenta)         v="#FF3DE0" ;;
        pink|flamingo)   v="#FF7AA8" ;;
        gray|grey)       v="#B0B6BE" ;;
    esac

    case "$v" in
        '#'*)
            h="${v#\#}"
            case "$h" in
                [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])
                    r="${h:0:2}"; g="${h:2:2}"; b="${h:4:2}"
                    ;;
                [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])
                    r="${h:0:1}${h:0:1}"; g="${h:1:1}${h:1:1}"; b="${h:2:1}${h:2:1}"
                    ;;
                *) return 1 ;;
            esac
            printf '%d;%d;%d' "0x$r" "0x$g" "0x$b"
            return 0
            ;;
        *';'*';'*)
            IFS=';' read -r r g b <<< "$v"
            for h in "$r" "$g" "$b"; do
                case "$h" in
                    ''|*[!0-9]*) return 1 ;;
                esac
                [ "$h" -le 255 ] || return 1
            done
            printf '%d;%d;%d' "$r" "$g" "$b"
            return 0
            ;;
    esac
    return 1
}

# Git 브랜치 / worktree / dirty 상태 (cwd가 git repo가 아니거나 git이 없으면 조용히 스킵)
# cwd는 위에서 이미 "실제 현재 디렉터리"로 확정됨(캐시 미개입) → 항상 올바른 워크트리 표시.
git_info=""
if [ -n "$cwd" ] && command -v git &>/dev/null && git -C "$cwd" rev-parse --is-inside-work-tree &>/dev/null; then
    branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
        branch=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
    fi

    if [ -n "$branch" ]; then
        # linked worktree 여부 판별: git-dir 경로에 /worktrees/ 가 포함되면 linked worktree
        # git-common-dir 은 같은 호출로 함께 받는다(메인 체크아웃 루트 = 그 dirname).
        IFS=$'\n' read -r -d '' git_dir git_common_dir < <(
            git -C "$cwd" rev-parse --git-dir --git-common-dir 2>/dev/null; printf '\0'
        )
        # --git-common-dir 미지원 등으로 통째로 실패하면 기존 방식으로 폴백(워크트리명은 유지, 색만 포기)
        if [ -z "$git_dir" ]; then
            git_dir=$(git -C "$cwd" rev-parse --git-dir 2>/dev/null)
            git_common_dir=""
        fi
        worktree_name=""
        case "$git_dir" in
            */worktrees/*|*\\worktrees\\*)
                toplevel=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
                if [ -n "$toplevel" ]; then
                    worktree_name=$(basename "$toplevel")
                fi
                ;;
        esac

        # 워크트리 색상 조회 (linked worktree 일 때만)
        wt_rgb=""
        if [ -n "$worktree_name" ]; then
            wt_color=""
            # linked worktree 에서 git-common-dir 은 항상 절대경로 <메인>/.git
            if [ -n "$git_common_dir" ]; then
                main_root=$(dirname "$git_common_dir")
                wt_color=$(lookup_color "$worktree_name" "$main_root/.claude/$COLOR_FILE_NAME")
            fi
            if [ -z "$wt_color" ]; then
                wt_color=$(lookup_color "$worktree_name" "$HOME/.claude/$COLOR_FILE_NAME")
            fi
            if [ -n "$wt_color" ]; then
                wt_rgb=$(resolve_rgb "$wt_color") || wt_rgb=""
            fi
        fi

        # dirty/clean 상태
        status_out=$(git -C "$cwd" status --porcelain 2>/dev/null)
        if [ -n "$status_out" ]; then
            dirty_indicator="$(printf '\033[38;2;245;169;127m\xe2\x97\x8f\033[0m')"
        else
            dirty_indicator="$(printf '\033[38;2;166;218;149m\xe2\x9c\x93\033[0m')"
        fi

        git_info="$(printf '\033[38;2;138;173;244m%s\033[0m' "$branch")"
        if [ -n "$worktree_name" ]; then
            if [ -n "$wt_rgb" ]; then
                # (█ DevA) — 네모만 지정색, 이름은 기존 mauve 유지
                git_info="${git_info}$(printf ' \033[38;2;198;160;246m(\033[38;2;%sm\xe2\x96\x88\033[38;2;198;160;246m %s)\033[0m' "$wt_rgb" "$worktree_name")"
            else
                git_info="${git_info}$(printf ' \033[38;2;198;160;246m(%s)\033[0m' "$worktree_name")"
            fi
        fi
        git_info="${git_info} ${dirty_indicator}"
    fi
fi

# 비활성 게이지 생성 함수 (20칸, 값 없을 때 사용)
make_inactive_gauge() {
    printf '\033[38;2;70;70;70m▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒\033[0m'
}

# 게이지 생성 함수 (20칸, 밝은색→진한색 그라데이션)
make_gauge() {
    local pct="$1"
    local family="${2:-usage}"
    local filled=$(( (pct * 20 + 50) / 100 ))

    local sr sg sb tr tg tb er eg eb
    if [ "$family" = "ctx" ]; then
        sr=216; sg=202; sb=229   # 밝은 라벤더
        tr=198; tg=160; tb=246   # #C6A0F6
        er=54;  eg=26;  eb=90    # 어두운 퍼플
    else
        sr=229; sg=189; sb=198   # 밝은 코럴
        tr=237; tg=135; tb=150   # #ED8796
        er=66;  eg=33;  eb=39    # 어두운 와인
    fi

    local gauge=""
    for ((i=0; i<20; i++)); do
        if [ $i -lt $filled ]; then
            local r g b
            if [ $filled -le 1 ]; then
                r=$tr; g=$tg; b=$tb
            else
                r=$(( sr + (tr - sr) * i / (filled - 1) ))
                g=$(( sg + (tg - sg) * i / (filled - 1) ))
                b=$(( sb + (tb - sb) * i / (filled - 1) ))
            fi
            gauge="${gauge}$(printf '\033[38;2;%d;%d;%dm█\033[0m' "$r" "$g" "$b")"
        else
            gauge="${gauge}$(printf '\033[38;2;%d;%d;%dm█\033[0m' "$er" "$eg" "$eb")"
        fi
    done
    echo "$gauge"
}

sep="$(printf ' \033[38;2;100;100;100m|\033[0m ')"

# 첫번째 줄: [model] | [git] | [시간]
line1_parts=()
if [ -n "$model" ]; then
    line1_parts+=("$(printf '\033[38;2;238;212;159m%s\033[0m' "$model")")
fi
if [ -n "$git_info" ]; then
    line1_parts+=("$git_info")
fi
line1_parts+=("$(printf '\033[38;2;139;213;202m%s\033[0m' "$now")")

printf '%s' "${line1_parts[0]}"
for ((i=1; i<${#line1_parts[@]}; i++)); do
    printf '%s%s' "$sep" "${line1_parts[$i]}"
done
printf '\n'

# 두번째 줄: Context    [게이지 20칸] X% (값이 없으면 비활성 게이지 + 미확인 표시)
if [ -n "$used" ]; then
    gauge=$(make_gauge "$used" "ctx")
    printf '\033[38;2;198;160;246mContext    \033[0m%s \033[38;2;198;160;246m%s%%\033[0m\n' "$gauge" "$used"
else
    gauge=$(make_inactive_gauge)
    printf '\033[38;2;198;160;246mContext    \033[0m%s \033[38;2;90;90;90m미확인\033[0m\n' "$gauge"
fi

# 세번째 줄: Usage      [게이지 20칸] X% (리셋 HH:mm) (값이 없으면 비활성 게이지 + 미확인 표시)
if [ -n "$rate_used" ]; then
    gauge=$(make_gauge "$rate_used" "usage")
    if [ -n "$rate_reset" ]; then
        printf '\033[38;2;237;135;150mUsage      \033[0m%s \033[38;2;237;135;150m%s%% (리셋 %s)\033[0m\n' "$gauge" "$rate_used" "$rate_reset"
    else
        printf '\033[38;2;237;135;150mUsage      \033[0m%s \033[38;2;237;135;150m%s%%\033[0m\n' "$gauge" "$rate_used"
    fi
else
    gauge=$(make_inactive_gauge)
    printf '\033[38;2;237;135;150mUsage      \033[0m%s \033[38;2;90;90;90m미확인\033[0m\n' "$gauge"
fi
