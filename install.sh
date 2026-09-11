#!/usr/bin/env bash
#
# Link the shared skills and per-provider configs into every coding-agent CLI
# on this machine. Safe to re-run; run it again after adding a skill.
#
#   ./install.sh              link into providers that are set up on this machine
#   ./install.sh --all        link into every known provider, creating their dirs
#   ./install.sh --dry-run    print every step, change nothing
#
# Layout of this repo:
#
#   skills/<name>/SKILL.md    one skill, Agent Skills format, shared by all providers
#   providers/<provider>/...  files mirrored into that provider's config root
#
# A provider counts as "set up" when its config root exists (see PROVIDERS).
# Anything real that sits where a link needs to go is moved to
# ~/.agent-configs-backup/<timestamp>/, never deleted.

set -uo pipefail

DRY_RUN=false
ALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run|-n) DRY_RUN=true ;;
        --all)        ALL=true ;;
        -h|--help)    awk 'NR>2 && /^#/ { sub(/^# ?/, ""); print; next } NR>2 { exit }' "$0"; exit 0 ;;
        *)            printf 'unknown option: %s\n' "$1" >&2; exit 1 ;;
    esac
    shift
done

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.agent-configs-backup/$(date +%Y%m%d-%H%M%S)"

# provider | config root | skills dir (relative to root)
#
# The `agents` row is the vendor-neutral location (~/.agents/skills) that Codex,
# OpenCode and others read in addition to their own; it is always linked.
PROVIDERS=(
    "agents|$HOME/.agents|skills"
    "claude|$HOME/.claude|skills"
    "codex|$HOME/.codex|skills"
    "opencode|$HOME/.config/opencode|skill"
    "pi|$HOME/.pi/agent|skills"
    "gemini|$HOME/.gemini|skills"
    "copilot|$HOME/.copilot|skills"
    "cursor|$HOME/.cursor|skills"
    "amp|$HOME/.config/amp|skills"
)

if [[ -t 1 ]]; then
    C_RESET=$'\e[0m'; C_DIM=$'\e[2m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_BLUE=$'\e[34m'
else
    C_RESET=''; C_DIM=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''
fi

WARNINGS=()
step() { printf '\n%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '    %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
skip() { printf '    %s·%s %s\n' "$C_DIM" "$C_RESET" "$*"; }
warn() { printf '    %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; WARNINGS+=("$*"); }

run() {
    if $DRY_RUN; then
        printf '    %s$ %s%s\n' "$C_DIM" "$*" "$C_RESET"
        return 0
    fi
    "$@"
}

same_target() {
    [[ "$(readlink -f -- "$1" 2>/dev/null)" == "$(readlink -f -- "$2")" ]]
}

# link SRC DEST: symlink DEST -> SRC, moving anything else out of the way.
link() {
    local src=$1 dest=$2 rel=${2#"$HOME/"}
    if [[ -L $dest || -e $dest ]]; then
        if same_target "$dest" "$src"; then
            skip "$rel"
            return
        fi
        run mkdir -p "$(dirname "$BACKUP_DIR/$rel")"
        run mv "$dest" "$BACKUP_DIR/$rel"
        warn "backed up $rel -> $BACKUP_DIR/$rel"
    fi
    run mkdir -p "$(dirname "$dest")"
    run ln -s "$src" "$dest" && ok "$rel -> ${src#"$REPO_DIR/"}"
}

provider_active() {
    local name=$1 root=$2
    [[ $name == agents ]] && return 0
    $ALL && return 0
    [[ -d $root ]]
}

step "Skills"
for entry in "${PROVIDERS[@]}"; do
    IFS='|' read -r name root skills_sub <<<"$entry"
    if ! provider_active "$name" "$root"; then
        skip "$name: $root not present (use --all to force)"
        continue
    fi
    for skill in "$REPO_DIR"/skills/*/; do
        skill=${skill%/}
        [[ -f $skill/SKILL.md ]] || continue
        link "$skill" "$root/$skills_sub/$(basename "$skill")"
    done
done

step "Provider configs"
for entry in "${PROVIDERS[@]}"; do
    IFS='|' read -r name root _ <<<"$entry"
    [[ -d $REPO_DIR/providers/$name ]] || continue
    if ! provider_active "$name" "$root"; then
        skip "$name: $root not present"
        continue
    fi
    while IFS= read -r -d '' src; do
        link "$src" "$root/${src#"$REPO_DIR/providers/$name/"}"
    done < <(find "$REPO_DIR/providers/$name" -type f -print0)
done

step "Done"
if ((${#WARNINGS[@]})); then
    printf '    %s%d warning(s):%s\n' "$C_YELLOW" "${#WARNINGS[@]}" "$C_RESET"
    printf '      - %s\n' "${WARNINGS[@]}"
fi
