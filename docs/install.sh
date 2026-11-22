#!/usr/bin/env bash
# claude-statusline installer — https://github.com/alp82/claude-statusline
#
#   curl -fsSL https://alp82.github.io/claude-statusline/install.sh | bash
#
# Lives in docs/ because docs/ is the GitHub Pages root — that is what makes the
# one-liner above short. It is the only copy; the raw.githubusercontent URL
# (…/main/docs/install.sh) serves the same file.
#
# Drops statusline.sh into your Claude Code config dir, points settings.json's
# statusLine at it, and installs the subagent-rows plugin (the agent panel
# rows) with the claude CLI. Idempotent: re-running upgrades in place. Any
# file it overwrites or removes — including on --uninstall — is backed up
# next to the original first.

set -euo pipefail

REPO="alp82/claude-statusline"
REF="${CLAUDE_STATUSLINE_REF:-main}"
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
PATCH_SETTINGS=1
UNINSTALL=0

# All are cleaned up by one trap, so uninstall (which never fetches) can share
# the settings writer with install without tripping over an unset $tmp.
tmp=''
settings_tmp=''
trap 'rm -f "$tmp" "$settings_tmp"' EXIT

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[38;2;138;138;138m'; CLAY=$'\033[38;2;217;119;87m'
  GREEN=$'\033[38;2;140;194;74m'; RED=$'\033[38;2;220;60;60m'
  RESET=$'\033[0m'
else
  BOLD=''; DIM=''; CLAY=''; GREEN=''; RED=''; RESET=''
fi

step() { printf '%s→%s %s\n' "$CLAY" "$RESET" "$*"; }
ok()   { printf '%s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s!%s %s\n' "$RED" "$RESET" "$*" >&2; }
die()  { printf '%s✗%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

usage() {
  cat <<EOF
${BOLD}claude-statusline installer${RESET}

Installs the statusline, or updates it in place if you already have it.

  curl -fsSL https://alp82.github.io/claude-statusline/install.sh | bash
  curl -fsSL https://alp82.github.io/claude-statusline/install.sh | bash -s -- --no-settings
  curl -fsSL https://alp82.github.io/claude-statusline/install.sh | bash -s -- --uninstall

Options:
  --dir <path>     Claude Code config dir (default: \$CLAUDE_CONFIG_DIR or ~/.claude)
  --ref <ref>      branch or tag to install from (default: $REF); the
                   plugin is pinned to it too
  --no-settings    install statusline.sh only; print the settings.json
                   snippet and the plugin commands instead of running them.
                   With --uninstall, remove the scripts but leave
                   settings.json and the plugin alone.
  --uninstall      remove the scripts, drop the statusLine and
                   subagentStatusLine entries from settings.json, and
                   uninstall the subagent-rows plugin and its marketplace,
                   backing files up first
  -h, --help       this help
EOF
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --dir)          CONFIG_DIR=${2:?--dir needs a path}; shift 2 ;;
    --ref)          REF=${2:?--ref needs a ref}; shift 2 ;;
    --no-settings)  PATCH_SETTINGS=0; shift ;;
    --uninstall)    UNINSTALL=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    *)              usage >&2; die "unknown option: $1" ;;
  esac
done

# Claude Code runs the statusLine command from the *project* directory, so a
# relative path would resolve nowhere and the statusline would silently never
# render. Anchor it here, while $PWD still means what the user typed it against.
[[ $CONFIG_DIR == /* ]] || CONFIG_DIR="$PWD/${CONFIG_DIR#./}"

# REF is interpolated into a URL, and curl removes dot-segments before the
# request — so `--ref ../../someone-else/repo/main` would quietly escape the
# REPO pin above while the printed URL still reads as this repo.
[[ $REF =~ ^[A-Za-z0-9._/-]+$ && $REF != *..* ]] || die "invalid --ref: $REF"

# A commit SHA is not the pin it looks like: raw.githubusercontent serves any
# object in the repo's *fork network* under this repo's path, so a fork's SHA
# fetches the fork's code from a URL that still reads as ours. Branch and tag
# names resolve per-repo and cannot, which is all --ref ever advertised.
# Case-insensitive and down to 4 chars: raw.githubusercontent resolves an
# uppercased SHA and any unambiguous short prefix just as readily. The cost is
# that an all-hex tag of 4-40 chars is unusable — such a string *is* a valid
# short SHA, so there is nothing to tell them apart by.
if [[ $REF =~ ^[0-9a-fA-F]{4,40}$ ]]; then
  die "invalid --ref: $REF — branch or tag names only, not commit SHAs."
fi

# --- dependencies -----------------------------------------------------------
# jq parses the statusline JSON on every render, so it is a hard requirement of
# the script itself, not just of this installer. Uninstalling fetches nothing,
# so curl is an install-only need.
deps=(jq)
(( UNINSTALL )) || deps+=(curl)
for dep in "${deps[@]}"; do
  command -v "$dep" >/dev/null 2>&1 \
    || die "$dep is required (statusline.sh needs it too) — install it and re-run."
done

TARGET="$CONFIG_DIR/statusline.sh"
# Only cleaned up now: an older install left this script and a
# subagentStatusLine entry behind, which Claude Code no longer runs.
SUB_TARGET="$CONFIG_DIR/subagent-statusline.sh"
SETTINGS="$CONFIG_DIR/settings.json"
SOURCE_URL="https://raw.githubusercontent.com/$REPO/$REF/statusline.sh"
# The agent panel rows are the subagent-rows plugin. Its marketplace is this
# repo (.claude-plugin/marketplace.json names it claude-statusline), and
# #ref pins it, and so the plugin, to the same ref as statusline.sh.
MARKETPLACE="claude-statusline"
PLUGIN="subagent-rows@$MARKETPLACE"
MARKET_SRC="$REPO#$REF"

# A symlinked settings.json means a dotfile manager (stow/chezmoi/yadm) owns it.
# Unlike $TARGET below, follow this one: it points at the user's own config, so
# writing through the link keeps their repo the source of truth. Replacing the
# link with a regular file would strand the wiring at the next `stow`/`apply`.
if [[ -L $SETTINGS ]]; then
  resolved=$(readlink -f "$SETTINGS" 2>/dev/null) || resolved=''
  [[ -n $resolved ]] && SETTINGS=$resolved
fi

# Claude Code runs statusLine.command *in a shell* — that is why the documented
# ~/.claude/statusline.sh form works at all. So a config dir containing spaces
# has to arrive quoted, or the shell word-splits it and the statusline silently
# never renders. Paths needing no quoting stay bare, so existing installs still
# compare equal and re-running remains a no-op.
shellquote() {
  if [[ $1 == *[^A-Za-z0-9._/-]* ]]; then
    printf "'%s'" "${1//\'/\'\\\'\'}"
  else
    printf '%s' "$1"
  fi
}
CMD=$(shellquote "$TARGET")
SUB_CMD=$(shellquote "$SUB_TARGET")

# The statusline reads the working tree on every render. Events alone leave
# those counts stale while the session sits idle and a subagent writes files,
# so the line also re-runs on a timer. Five seconds is well under the cost of
# the two git calls and keeps the ↻ countdowns honest.
REFRESH=5

settings_snippet() {
  jq -n --arg cmd "$CMD" --argjson every "$REFRESH" '{
    statusLine: {type: "command", command: $cmd, refreshInterval: $every}
  }'
}

# Rewrite settings.json through the given jq program, atomically. Args are
# passed to jq verbatim, with $SETTINGS as its input file.
write_settings() {
  # Temp file beside the real settings.json (which may live in a dotfile repo,
  # see above) so the mv is a real rename(2), not a cross-device copy — and out
  # of world-writable /tmp.
  settings_tmp=$(mktemp "${SETTINGS%/*}/.settings.json.XXXXXX")
  jq "$@" "$SETTINGS" > "$settings_tmp" || die "failed to update $SETTINGS"
  # mv carries the temp file's mode, so match the original first: a
  # settings.json deliberately kept at 0600 must not come back 0644.
  if ! chmod --reference="$SETTINGS" "$settings_tmp" 2>/dev/null; then
    # BSD chmod (macOS) has no --reference; read the mode with BSD stat.
    # -L: stat defaults to lstat(2), and a symlink's own mode is 0777 —
    # copying that onto a file holding API keys would publish it.
    mode=$(stat -Lf '%Lp' "$SETTINGS" 2>/dev/null) || mode=''
    [[ $mode =~ ^[0-7]{3,4}$ ]] || mode=600
    chmod "$mode" "$settings_tmp"
  fi
  mv "$settings_tmp" "$SETTINGS" || die "failed to update $SETTINGS"
  settings_tmp=''
}

# Is this statusLine command one we wrote? The tilde form is what the old README
# recipe told people to paste, so it counts as ours for the default config dir.
is_ours() {
  [[ $1 == "$CMD" ]] \
    || { [[ $TARGET == "$HOME/.claude/statusline.sh" ]] && [[ $1 == "~/.claude/statusline.sh" ]]; }
}

# The same question for the subagentStatusLine an older install (or the old
# README recipe, in the tilde form) wrote.
is_our_sub() {
  [[ $1 == "$SUB_CMD" ]] \
    || { [[ $SUB_TARGET == "$HOME/.claude/subagent-statusline.sh" ]] && [[ $1 == "~/.claude/subagent-statusline.sh" ]]; }
}

# The claude CLI, aimed at the same config dir as everything else. Only a
# --dir away from the default sets CLAUDE_CONFIG_DIR, because setting it at
# all changes where Claude Code keeps its state; the default unsets an
# inherited one for the same reason. </dev/null: under `curl | bash` stdin
# is this script, and claude must not read it.
claude_cli() {
  if [[ ${CONFIG_DIR%/} == "$HOME/.claude" ]]; then
    env -u CLAUDE_CONFIG_DIR claude "$@" </dev/null
  else
    CLAUDE_CONFIG_DIR="$CONFIG_DIR" claude "$@" </dev/null
  fi
}
# The same prefix for a claude command printed for the user to run.
cli_env() {
  [[ ${CONFIG_DIR%/} == "$HOME/.claude" ]] || printf 'CLAUDE_CONFIG_DIR=%s ' "$(shellquote "$CONFIG_DIR")"
}
has_claude()      { command -v claude >/dev/null 2>&1; }
has_plugin()      { claude_cli plugin list --json 2>/dev/null | jq -e --arg p "$PLUGIN" 'any(.[]; .id == $p)' >/dev/null 2>&1; }
has_marketplace() { claude_cli plugin marketplace list --json 2>/dev/null | jq -e --arg m "$MARKETPLACE" 'any(.[]; .name == $m)' >/dev/null 2>&1; }
# Where the claude-statusline marketplace was added from, as owner/repo#ref
# (one added without a ref follows the default branch, main); empty when it
# is not added. Callers write `x=$(marketplace_src) || x=''`.
marketplace_src() {
  claude_cli plugin marketplace list --json 2>/dev/null \
    | jq -r --arg m "$MARKETPLACE" 'first(.[] | select(.name == $m) | "\(.repo // "")#\(.ref // "main")") // empty' 2>/dev/null
}

# The commands that install, or uninstall, the plugin by hand.
plugin_hint() {
  local pre; pre=$(cli_env)
  printf '  %sclaude plugin marketplace add %s\n  %sclaude plugin install %s\n' "$pre" "$MARKET_SRC" "$pre" "$PLUGIN"
}
plugin_uninstall_hint() {
  local pre; pre=$(cli_env)
  printf '  %sclaude plugin uninstall %s\n  %sclaude plugin marketplace remove %s\n' "$pre" "$PLUGIN" "$pre" "$MARKETPLACE"
}

# --- uninstall ---------------------------------------------------------------
if (( UNINSTALL )); then
  changed=0
  for t in "$TARGET" "$SUB_TARGET"; do
    # -L before -e: a symlink to a deleted target fails -e, and leaving it behind
    # would keep Claude Code running a statusLine command that cannot resolve.
    if [[ -L $t || -e $t ]]; then
      # Same rule as installing: never destroy what was there without a copy. cp -P
      # keeps a symlink a symlink, so the path it pointed at survives in the backup.
      cp -Pp "$t" "$t.bak"
      rm -f "$t"
      ok "removed $t ${DIM}(backup: $t.bak)${RESET}"
      changed=1
    else
      step "no script at $t"
    fi
  done

  if (( ! PATCH_SETTINGS )); then
    step "leaving $SETTINGS alone (--no-settings)"
  elif [[ ! -f $SETTINGS ]]; then
    step "no settings.json at $SETTINGS"
  elif ! shape=$(jq -r '
        if type == "object" or type == "null"
        then (.statusLine | type)
        else "root"
        end' "$SETTINGS" 2>/dev/null); then
    warn "$SETTINGS is not valid JSON — leaving it alone; drop the statusLine entry yourself."
  elif [[ $shape == root ]]; then
    warn "$SETTINGS is not a JSON object — leaving it alone; drop the statusLine entry yourself."
  elif [[ $shape == null ]]; then
    step "$SETTINGS has no statusLine entry"
  elif [[ $shape != object ]]; then
    warn "$SETTINGS has a statusLine that is not an object — leaving it alone."
  else
    current=$(jq -r '.statusLine.command // ""' "$SETTINGS")
    if [[ -z $current ]]; then
      warn "$SETTINGS has a statusLine with no command — leaving it alone."
    elif ! is_ours "$current"; then
      # Someone else's statusline, or a hand-edited path. Deleting the entry
      # would take their statusline away along with ours.
      warn "$SETTINGS points statusLine at something else — leaving it alone:"
      warn "  $current"
    else
      cp -p "$SETTINGS" "$SETTINGS.bak"
      write_settings 'del(.statusLine)'
      ok "unwired $SETTINGS ${DIM}(backup: $SETTINGS.bak)${RESET}"
      changed=1
    fi
  fi

  # The subagentStatusLine entry ships with the same install, so it goes the
  # same way — but only when it still points at our script.
  if (( PATCH_SETTINGS )) && [[ -f $SETTINGS ]]; then
    sub_current=$(jq -r '.subagentStatusLine.command // ""' "$SETTINGS" 2>/dev/null) || sub_current=''
    if [[ -n $sub_current && $sub_current == "$SUB_CMD" ]]; then
      [[ -f $SETTINGS.bak ]] || cp -p "$SETTINGS" "$SETTINGS.bak"
      write_settings 'del(.subagentStatusLine)'
      ok "unwired subagentStatusLine from $SETTINGS"
      changed=1
    elif [[ -n $sub_current ]]; then
      warn "$SETTINGS points subagentStatusLine at something else — leaving it alone:"
      warn "  $sub_current"
    fi
  fi

  # The only state the statusline creates on its own: the throttled Fable-usage
  # fetch. statusline.sh hardcodes these under $HOME, so --dir does not move
  # them. Regenerable, so they go without a backup.
  for stale in "$HOME/.claude/cache/oauth-usage.json" "$HOME/.claude/cache/oauth-usage.attempt"; do
    if [[ -e $stale ]]; then
      rm -f "$stale"
      step "removed cached usage ${DIM}${stale}${RESET}"
      changed=1
    fi
  done

  printf '\n'
  if (( changed )); then
    ok "${BOLD}Done.${RESET} Open a new Claude Code session; the statusline is gone."
    printf '%sBackups are left in place — delete the .bak files when you are happy.%s\n' \
      "$DIM" "$RESET"
  else
    ok "${BOLD}Nothing to remove.${RESET} No claude-statusline install found in $CONFIG_DIR."
  fi
  exit 0
fi

# --- fetch ------------------------------------------------------------------
fetch() {
  local url=$1 dest=$2
  curl -fsSL --connect-timeout 10 --max-time 120 "$url" -o "$dest" \
    || die "download failed: $url"
  [[ -s $dest ]] || die "downloaded an empty file from $url"
  head -n 1 "$dest" | grep -q '^#!/usr/bin/env bash$' \
    || die "$url did not look like a statusline script"
}

tmp=$(mktemp)
step "fetching statusline.sh @ $REF"
fetch "$SOURCE_URL" "$tmp"

# --- install ----------------------------------------------------------------
# 0700: the config dir holds settings.json, which routinely carries API keys.
mkdir -p -m 700 "$CONFIG_DIR"

install_script() {
  local src=$1 target=$2
  if [[ -L $target ]]; then
    # The old README recipe symlinked this at a git clone. Writing through the
    # link would clobber the clone (including uncommitted work), so break it
    # instead — but say so, because that clone stops being what Claude Code loads.
    # cp -P copies the link rather than its target, so the path it pointed at is
    # recoverable from the backup and nothing in the clone is touched.
    cp -Pp "$target" "$target.bak"
    warn "$target was a symlink → $(readlink "$target")"
    warn "replacing it with a real file; that path is no longer what Claude Code loads."
    step "backed up the symlink → $target.bak"
  elif [[ -e $target ]] && ! cmp -s "$src" "$target"; then
    cp -p "$target" "$target.bak"
    step "backed up existing script → $target.bak"
  fi
  rm -f "$target"
  cp "$src" "$target"
  chmod +x "$target"
  ok "installed $target"
}

install_script "$tmp" "$TARGET"
install_script "$sub_tmp" "$SUB_TARGET"

# --- settings ---------------------------------------------------------------
wired=0
if (( PATCH_SETTINGS )); then
  had_settings=1
  created=1
  if [[ ! -f $SETTINGS ]]; then
    had_settings=0
    # A dangling symlink lands here with an unreachable target, so this can fail.
    (umask 077; printf '{}\n' > "$SETTINGS") 2>/dev/null || created=0
  fi

  # One jq call answers both questions: is the file parseable at all (exit
  # status), and is it a shape we can safely patch (stdout). An empty or `null`
  # settings.json is unusual but not corrupt — the write below normalises those
  # to an object — but a top-level array/string/number is not ours to rewrite.
  if (( ! created )); then
    warn "cannot write $SETTINGS — is it a symlink to somewhere that no longer exists?"
    warn "add this yourself:"
    settings_snippet
  elif ! shape=$(jq -r '
        if type == "object" or type == "null"
        then (.statusLine | type)
        else "root"
        end' "$SETTINGS" 2>/dev/null); then
    warn "$SETTINGS is not valid JSON — leaving it alone. Add this yourself:"
    settings_snippet
  elif [[ $shape == root ]]; then
    warn "$SETTINGS is not a JSON object — leaving it alone. Add this yourself:"
    settings_snippet
  elif [[ $shape =~ ^(array|string|number|boolean)$ ]]; then
    warn "$SETTINGS has a statusLine that is not an object — leaving it alone. Add this yourself:"
    settings_snippet
  else
    current=$(jq -r '.statusLine.command // ""' "$SETTINGS")
    sub_current=$(jq -r '.subagentStatusLine.command // ""' "$SETTINGS")
    # a previous install (or the old README recipe) may have written the tilde form
    if is_ours "$current" && [[ $sub_current == "$SUB_CMD" ]]; then
      ok "settings.json already points at both"
      wired=1
    else
      note=''
      if (( had_settings )); then
        cp -p "$SETTINGS" "$SETTINGS.bak"
        note=" ${DIM}(backup: $SETTINGS.bak)${RESET}"
        if [[ -n $current ]] && ! is_ours "$current"; then
          step "replacing existing statusLine command ($current)"
        fi
        if [[ -n $sub_current && $sub_current != "$SUB_CMD" ]]; then
          step "replacing existing subagentStatusLine command ($sub_current)"
        fi
      fi
      write_settings -n --arg cmd "$CMD" --arg sub "$SUB_CMD" --argjson every "$REFRESH" \
        'input? // {}
         | .statusLine = {type: "command", command: $cmd, refreshInterval: $every}
         | .subagentStatusLine = {type: "command", command: $sub}'
      ok "wired up $SETTINGS$note"
      wired=1
    fi
  fi
else
  printf '\n%sAdd this to %s:%s\n' "$BOLD" "$SETTINGS" "$RESET"
  settings_snippet
fi

# --- done -------------------------------------------------------------------
printf '\n'
if (( PATCH_SETTINGS )) && (( ! wired )); then
  die "statusline.sh is installed, but $SETTINGS was not wired up — see above."
fi

if (( PATCH_SETTINGS )); then
  ok "${BOLD}Done.${RESET} Open a new Claude Code session to see the statusline."
else
  ok "${BOLD}Done.${RESET} Add the snippet above to $SETTINGS, then open a new Claude Code session."
fi
