#!/usr/bin/env bash
# Claude Code subagent statusline: one row per agent in the agent panel, each
# with its own context bar:  name ▓▓░░░ 12% 34k · Opus 5 · high · description
# Every field is a column: the whole payload is read first, each column is
# measured across all the rows, and the rows are then drawn on that grid.
# Reads {columns, tasks:[...]} JSON on stdin, writes one {"id","content"} JSON
# line per task (see https://code.claude.com/docs/en/statusline.md).
# Palette, thresholds, bar geometry and effort labels mirror statusline.sh —
# change one, change the other.

# --- settings. The same ~/.statuslinerc as statusline.sh, sourced the same
# way: plain shell, and a variable already set in the environment wins.
STATUSLINE_RC=${STATUSLINE_RC:-$HOME/.statuslinerc}
if [[ -r $STATUSLINE_RC ]]; then
  rc_env=$(declare -p COMPACT 2>/dev/null)
  # shellcheck source=/dev/null
  source "$STATUSLINE_RC"
  [[ -n $rc_env ]] && eval "$rc_env"
  unset rc_env
fi

input=$(cat)
columns=$(jq -r '.columns // 80' <<<"$input")
# A non-integer would be fatal, not ignored: bash aborts the script when an
# arithmetic *assignment* fails, and the panel would come out empty.
[[ $columns =~ ^[0-9]+$ ]] || columns=80

RESET=$'\033[0m'
DIM=$'\033[38;2;138;138;138m'
SEP=$'\033[38;2;55;55;55m'
NAME=$'\033[38;5;74m'
TRACK='48;2;55;55;55'

# context color: green < 25, yellow 25-49, red >= 50 (same as statusline.sh)
ctx_color() {
  if   (( $1 >= 50 )); then echo '38;2;220;60;60'
  elif (( $1 >= 25 )); then echo '38;2;220;200;60'
  else                     echo '38;2;140;194;74'
  fi
}

# bar <pct> <width> — solid fill with 1/8-block resolution on a dark track
bar() {
  local pct=$1 w=$2 fg partials=("" "▏" "▎" "▍" "▌" "▋" "▊" "▉")
  (( pct < 0 )) && pct=0; (( pct > 100 )) && pct=100
  fg=$(ctx_color "$pct")
  local eighths=$(( pct * w * 8 / 100 ))
  local full=$(( eighths / 8 )) part=$(( eighths % 8 ))
  local out="" i
  for (( i = 0; i < full; i++ )); do out+="█"; done
  out+="${partials[$part]}"
  local used=$(( full + (part > 0 ? 1 : 0) ))
  printf '\033[%s;%sm%s%*s\033[0m' "$TRACK" "$fg" "$out" $(( w - used )) ""
}

# vglyph <pct> — one block glyph whose height is the percentage, in eighths
# (same as statusline.sh). ▁ is the floor so 0% still shows a base.
vglyph() {
  local pct=$1 g=("▁" "▁" "▂" "▃" "▄" "▅" "▆" "▇" "█")
  (( pct < 0 )) && pct=0; (( pct > 100 )) && pct=100
  printf '%s' "${g[$(( (pct * 8 + 50) / 100 ))]}"
}

# COMPACT — the same list statusline.sh reads. With `ctx` in it the context
# bar folds into a single block glyph, and the grid narrows with it: the meter
# is CTX_CELLS wide on every row, drawn or not.
COMPACT=${COMPACT-fable}
is_compact() { [[ ",${COMPACT// /}," == *",$1,"* ]]; }
CTX_CELLS=10
is_compact ctx && CTX_CELLS=1

# ctx_meter <pct> — the context gauge, CTX_CELLS wide
ctx_meter() {
  if (( CTX_CELLS == 1 )); then
    printf '\033[%s;%sm%s\033[0m' "$(ctx_color "$1")" "$TRACK" "$(vglyph "$1")"
  else
    bar "$1" "$CTX_CELLS"
  fi
}

# --- display width. A terminal counts columns; bash counts characters. CJK
# and emoji take two columns, and under a non-UTF-8 locale bash counts bytes,
# where cutting a string mid-sequence would write invalid UTF-8 to the
# terminal. `UTF8` records whether this shell sees characters at all. ASCII,
# which is almost every name, skips the whole thing.
utf8_probe='ää'
[[ ${#utf8_probe} == 2 ]] && UTF8=1 || UTF8=''

is_ascii() { [[ $1 != *[^\ -~]* ]]; }

# wide <codepoint> — the ranges a terminal draws two columns wide
wide() {
  local c=$1
  (( c >= 0x1100 )) || return 1
  (( c <= 0x115f || c == 0x2329 || c == 0x232a \
     || ( c >= 0x2e80 && c <= 0xa4cf && c != 0x303f ) \
     || ( c >= 0xac00 && c <= 0xd7a3 ) || ( c >= 0xf900 && c <= 0xfaff ) \
     || ( c >= 0xfe30 && c <= 0xfe6f ) || ( c >= 0xff00 && c <= 0xff60 ) \
     || ( c >= 0xffe0 && c <= 0xffe6 ) || ( c >= 0x1f300 && c <= 0x1faff ) \
     || ( c >= 0x20000 && c <= 0x3fffd ) ))
}

# vis_len <string> — how many columns the string occupies
vis_len() {
  local s=$1 n=0 i cp
  if is_ascii "$s" || [[ -z $UTF8 ]]; then echo "${#s}"; return; fi
  for (( i = 0; i < ${#s}; i++ )); do
    printf -v cp '%d' "'${s:i:1}"
    if wide "$cp"; then n=$(( n + 2 )); else n=$(( n + 1 )); fi
  done
  echo "$n"
}

# vis_cut <string> <columns> — the longest prefix that fits in that many
# columns. A shell that cannot see characters leaves a multibyte string whole
# rather than splitting a sequence in half.
vis_cut() {
  local s=$1 max=$2
  is_ascii "$s" && { echo "${s:0:max}"; return; }
  [[ -z $UTF8 ]] && { echo "$s"; return; }
  local n=0 i cp w out=''
  for (( i = 0; i < ${#s}; i++ )); do
    printf -v cp '%d' "'${s:i:1}"
    w=1; wide "$cp" && w=2
    (( n + w > max )) && break
    out+=${s:i:1}; n=$(( n + w ))
  done
  echo "$out"
}

# short_model <model_id> — the panel sends a model id, not a display name, so
# the name is read off the id: claude-opus-5[1m] -> Opus 5 1M,
# claude-sonnet-4-6-20260401 -> Sonnet 4.6, claude-3-7-sonnet-… -> Sonnet 3.7,
# claude-3-opus-… -> Opus 3. The pre-4 ids put the version before the family,
# so both of their forms are matched first: read the other way round, their
# date stamp becomes the version. A minor version also counts only when a
# separator follows it, for the same reason.
short_model() {
  local id=$1 onem="" fam ver
  [[ $id == *"[1m]"* ]] && onem=" 1M"
  if [[ $id =~ ([0-9]+)-([0-9]+)-(opus|sonnet|haiku) ]]; then
    fam=${BASH_REMATCH[3]}; ver="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
  elif [[ $id =~ ([0-9]+)-(opus|sonnet|haiku) ]]; then
    fam=${BASH_REMATCH[2]}; ver=${BASH_REMATCH[1]}
  elif [[ $id =~ (opus|sonnet|haiku|fable)-([0-9]+)(-([0-9]{1,2})([-@]|$))? ]]; then
    fam=${BASH_REMATCH[1]}; ver=${BASH_REMATCH[2]}
    [[ -n ${BASH_REMATCH[4]} ]] && ver+=".${BASH_REMATCH[4]}"
  else
    return                      # an id we do not recognise: print nothing
  fi
  case $fam in
    opus)   fam=Opus   ;;
    sonnet) fam=Sonnet ;;
    haiku)  fam=Haiku  ;;
    fable)  fam=Fable  ;;
  esac
  echo "${fam} ${ver}${onem}"
}

# effort_label <level> — same five levels as statusline.sh
effort_label() {
  case $1 in
    low)    echo "low"  ;;
    medium) echo "med"  ;;
    high)   echo "high" ;;
    xhigh)  echo "xhi"  ;;
    max)    echo "max"  ;;
    *)      echo ""     ;;
  esac
}

# a description shorter than this tells you nothing, so the model and the
# effort give up their columns before it does
DESC_FLOOR=20
# every variable-width field is padded to the widest string it can hold, so a
# row redraws without the columns after it shuffling sideways
PCT_CELLS=4      # '100%'
TOKENS_CELLS=4   # '999k'
SEP_CELLS=3      # ' · '

# fmt_tokens <count> — always in thousands: 1k … 999k (same as statusline.sh)
fmt_tokens() {
  local k=$(( ($1 + 500) / 1000 ))
  (( k < 1 )) && k=1
  (( k > 999 )) && k=999
  echo "${k}k"
}

# pad <string> <columns> — trailing spaces up to a column count. printf pads
# by bytes, so a name holding a non-ASCII character would come out short by a
# column per extra byte; measuring with ${#s} and printing only spaces keeps
# the two in step.
pad() {
  local n
  n=$(( $2 - $(vis_len "$1") ))
  (( n > 0 )) && printf '%s%*s' "$1" "$n" '' || printf '%s' "$1"
}

# --- first pass: derive every field, and measure the column each one needs.
# Every task arrives in one payload, so the whole grid is known before the
# first row is drawn.
ids=() names=() pcts=() toks=() mdls=() effs=() dscs=()
namew=0 mdlw=0 effw=0 have_desc=0 w=0
while IFS=$'\t' read -r id name status desc model effort tokens cws; do
  # every field carries the U+001F sentinel for "absent", the id included:
  # an empty leading field would shift every field after it
  [[ -z "$id" || $id == $'\x1f' ]] && continue
  [[ $name == $'\x1f' ]] && name="agent"
  [[ $status == $'\x1f' ]] && status=""
  [[ $desc == $'\x1f' ]] && desc=""
  [[ $model == $'\x1f' ]] && model=""
  [[ $effort == $'\x1f' ]] && effort=""
  [[ "$tokens" =~ ^[0-9]+$ ]] || tokens=0
  [[ "$cws" =~ ^[0-9]+$ ]] || cws=0

  if (( cws > 0 )); then
    pct=$(( tokens * 100 / cws ))
    tok_str=$(fmt_tokens "$tokens")
  else
    # model not resolved yet: no window size, so no percentage — tokens only.
    # A task that has not started really is at 0, so no round-up to 1k here.
    pct=-1
    (( tokens > 0 )) && tok_str=$(fmt_tokens "$tokens") || tok_str="0k"
  fi

  mdl=$(short_model "$model")
  eff=$(effort_label "$effort")
  ids+=("$id") names+=("$name") pcts+=("$pct") toks+=("$tok_str")
  mdls+=("$mdl") effs+=("$eff") dscs+=("$desc")
  w=$(vis_len "$name"); (( w > namew )) && namew=$w
  (( ${#mdl} > mdlw )) && mdlw=${#mdl}     # model and effort labels are ASCII
  (( ${#eff} > effw )) && effw=${#eff}
  [[ -n "$desc" ]] && have_desc=1
# Tab is an IFS whitespace character, so bash collapses a run of tabs and
# shifts every field after an empty one. d() keeps text fields non-empty with
# U+001F, cleared after the read (same trick as statusline.sh).
done < <(jq -r '(.tasks // [])[] |
  def d: if (. // "") == "" then "\u001f" else . end;
  [
    ((.id // "") | d),
    ((.name // "agent") | d),
    ((.status // "") | d),
    ((.description // "") | d),
    ((.model // "") | d),
    ((.effort // "") | d),
    (.tokenCount // 0),
    (.contextWindowSize // 0)
  ] | @tsv' <<<"$input")

# Name, bar, percentage and tokens are fixed-width, so the columns after them
# start in the same place on every row.
METER_CELLS=$(( CTX_CELLS + 1 + PCT_CELLS + 1 + TOKENS_CELLS ))
row_start=$(( namew + 1 + METER_CELLS ))

# A column is dropped for every row or for none: dropping it per row would
# break the alignment. The effort column goes first, then the model column.
# Only a panel that has descriptions reserves room for one.
floor=0
(( have_desc )) && floor=$(( SEP_CELLS + DESC_FLOOR ))
show_mdl=$(( mdlw > 0 )) show_eff=$(( effw > 0 ))
(( show_eff && row_start + show_mdl * (SEP_CELLS + mdlw) + SEP_CELLS + effw + floor > columns )) && show_eff=0
(( show_mdl && row_start + SEP_CELLS + mdlw + floor > columns )) && show_mdl=0

# --- second pass: draw the rows on that grid
for i in "${!ids[@]}"; do
  pct=${pcts[i]} tok_str=${toks[i]}
  if (( pct >= 0 )); then
    meter="$(ctx_meter "$pct") "$'\033['"$(ctx_color "$pct")m$(printf '%*s' "$PCT_CELLS" "${pct}%")${RESET}"
  else
    # no window size, so no bar and no percentage — the tokens still line up
    meter=$(printf '%*s' $(( CTX_CELLS + 1 + PCT_CELLS )) '')
  fi
  meter+=" ${DIM}$(printf '%*s' "$TOKENS_CELLS" "$tok_str")${RESET}"

  row="${NAME}$(pad "${names[i]}" "$namew")${RESET} ${meter}"
  row_len=$row_start

  # an empty cell still holds its column, so the description starts in the
  # same place whether or not this agent has a model
  for col in "$show_mdl:${mdls[i]}:$mdlw" "$show_eff:${effs[i]}:$effw"; do
    IFS=: read -r shown text width <<<"$col"
    (( shown )) || continue
    if [[ -n "$text" ]]; then
      row+=" ${SEP}·${RESET} ${DIM}$(pad "$text" "$width")${RESET}"
    else
      row+=$(printf '%*s' $(( SEP_CELLS + width )) '')
    fi
    row_len=$(( row_len + SEP_CELLS + width ))
  done

  # description, truncated so the row fits the panel width
  desc=${dscs[i]}
  room=$(( columns - row_len - SEP_CELLS ))
  if [[ -n "$desc" ]] && (( room > 4 )); then
    if (( $(vis_len "$desc") > room )); then
      cut=$(vis_cut "$desc" $(( room - 1 )))
      [[ $cut == "$desc" ]] || desc="${cut}…"
    fi
    row+=" ${SEP}·${RESET} ${DIM}${desc}${RESET}"
  fi

  jq -cn --arg id "${ids[i]}" --arg content "$row" '{id:$id, content:$content}'
done
