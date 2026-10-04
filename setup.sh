#!/usr/bin/env bash
# setup.sh: install termcheck into ~/bin.
#
# Run it on the machine you SSH into. termcheck changes nothing itself: it
# reports what gets through to your terminal, and what to change where
# something doesn't.
#
# Safe to re-run: it refreshes the installed script and skips anything that is
# already set up. The line it adds to your shell's startup file is marked with
# a comment.

# SC2016: the PATH line is meant to be written as it is. SC2088: the tildes
# are in text for you to read
# shellcheck disable=SC2016,SC2088
set -euo pipefail

# cd prints the directory when $CDPATH finds it, so discard its output
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null && pwd)
bin_dir=$HOME/bin
marker='# added by termcheck setup.sh'

ok()   { printf '  ok:    %s\n' "$*"; }
did()  { printf '  added: %s\n' "$*"; }
note() { printf '  note:  %s\n' "$*"; }
warn() { printf '  WARN:  %s\n' "$*"; }

# --- requirements -----------------------------------------------------------
echo "Requirements"
if (( BASH_VERSINFO[0] < 4 )); then
  echo "  termcheck needs bash 4 or later; this is bash $BASH_VERSION" >&2
  exit 1
fi
missing=
for cmd in stty base64 tr sed grep head wc cat sleep; do
  command -v "$cmd" > /dev/null || missing="$missing $cmd"
done
if [[ -n $missing ]]; then
  echo "  missing required commands:$missing (coreutils, sed and grep)" >&2
  exit 1
fi
ok "bash $BASH_VERSION; stty, base64, tr, sed, grep, head, wc, cat, sleep"
if command -v infocmp > /dev/null; then
  ok "infocmp, to check terminfo entries"
else
  note "no infocmp (ncurses): termcheck looks for terminfo entries by file instead"
fi
if [[ ! -d /proc/$$ ]]; then
  note "no /proc: termcheck can't tell SSH from mosh, and goes by \$SSH_CONNECTION"
fi

# --- install ----------------------------------------------------------------
echo "Install"
mkdir -p "$bin_dir"
install -m 0755 "$repo_dir/termcheck" "$bin_dir/termcheck"
ok "copied termcheck to $bin_dir/termcheck"

# --- PATH -------------------------------------------------------------------
echo "PATH"
case ":$PATH:" in
  *":$bin_dir:"*)
    ok "$bin_dir is on PATH"
    found=$(command -v termcheck || true)
    if [[ $found != "$bin_dir/termcheck" ]]; then
      warn "'termcheck' runs $found, which comes before $bin_dir on PATH"
    fi
    ;;
  *)
    # pick files that non-interactive shells read too, so that commands like
    # `ssh -t host termcheck` find termcheck
    case $(basename "${SHELL:-}") in
      bash) rc=$HOME/.bashrc ;;
      zsh)  rc=$HOME/.zshenv ;;   # read by every zsh; .zshrc is interactive only
      *)    rc= ;;
    esac
    line='export PATH="$HOME/bin:$PATH"'
    if [[ -z $rc ]]; then
      warn "add $bin_dir to PATH in your shell's startup file"
    elif grep -qsF "$line" "$rc"; then
      ok "$rc already adds ~/bin to PATH (open a new shell to pick it up)"
    else
      # add it at the top: many ~/.bashrc files, such as Debian's and
      # Ubuntu's, return early in non-interactive shells. The x stops $(...)
      # from removing the file's trailing newlines
      content=$(cat "$rc" 2> /dev/null; printf x)
      printf '%s\n%s\n\n%s' "$marker" "$line" "${content%x}" > "$rc"
      did "~/bin to PATH at the top of $rc (open a new shell, or run: source $rc)"
    fi
    ;;
esac

cat <<'EOF'

Done. In a new shell, run:

  termcheck

It reports what gets through to your terminal, and what to change where
something doesn't. `termcheck -t` also sends a test of each feature (it copies
a line of text to your clipboard). See README.md for what each line means.
EOF
