#!/usr/bin/env bash
#
#  latex-tools installer
#  =====================
#  One command sets up, on a fresh Mac (Apple Silicon or Intel) or Linux box:
#
#    1. TeX Live, user-local, no sudo, with every package but only the
#       languages you actually use (English, Spanish, French, Italian,
#       Portuguese, Japanese).
#    2. VS Code's LaTeX Workshop extension, wired to that TeX Live.
#    3. paperdiff, the command that diffs two versions of a paper.
#
#  The only prerequisite is VS Code (and even that is optional - everything
#  else still installs, and you can re-run this later).
#
#  Safety: nothing outside your home directory is touched, no sudo is ever
#  used, every file we modify is backed up first, and re-running is safe -
#  anything already installed and working is detected and left alone.
#
#  Usage:   ./install.sh [options]       (or double-click Install.command)
#           ./install.sh --dry-run       show what would happen, change nothing
#           ./install.sh --help

set -uo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
export REPO_DIR

# ------------------------------------------------------------- defaults ----
TL_PREFIX="$HOME/texlive"
TL_DOCS=1
TL_MINIMAL=0
DRYRUN=0
ASSUME_YES=0
DO_TEXLIVE=1
DO_VSCODE=1
DO_TOOLS=1
TEX_PATH_OPT=""
TL_BIN=""
TL_DIR=""
TL_YEAR=""
TL_PLATFORM=""
TL_REPO=""
VSCODE_OK=1
VSCODE_CLI=""
VSC_FLAVOUR="code"

# Logs live next to the installer, not in $HOME. Fall back to $HOME only if
# the repo directory is not writable (e.g. installed read-only).
if mkdir -p "$REPO_DIR/logs" 2>/dev/null && [ -w "$REPO_DIR/logs" ]; then
  LOGFILE="$REPO_DIR/logs/install-$(date +%Y%m%d-%H%M%S).log"
else
  LOGFILE="$HOME/latex-tools-install-$(date +%Y%m%d-%H%M%S).log"
fi
export LOGFILE

usage() {
  cat <<'EOF'
latex-tools installer

USAGE
  ./install.sh [options]

OPTIONS
  --dry-run         show exactly what would be done; change nothing at all
  --yes             never ask questions (for unattended installs)
  --prefix DIR      where TeX Live goes            (default ~/texlive)
  --no-docs         skip package documentation     (smaller, no `texdoc`)
  --tools-only      install ONLY paperdiff and paperflat, using the LaTeX you
                    already have. Nothing else on the machine is touched.
  --tex-path DIR    where your LaTeX lives, if it is not found automatically
                    (the bin directory, e.g. /usr/local/texlive/2025/bin/universal-darwin,
                    or the root of the installation)
  --skip-texlive    do not touch TeX Live
  --skip-vscode     do not touch VS Code
  --skip-tools      do not install paperdiff
  --minimal         install a tiny TeX Live (for testing this script only)
  -h, --help        this message

WHAT IT INSTALLS
  TeX Live        ~/texlive/<year>, user-local, no sudo, ~9 GB
                  all packages; languages limited to en es fr it pt ja
  VS Code         LaTeX Workshop extension + build recipes pointing at it
  paperdiff       ~/.local/bin/paperdiff

TOOLS ONLY
  Already have LaTeX and just want the two commands?
      ./install.sh --tools-only
  If your LaTeX is somewhere unusual:
      ./install.sh --tools-only --tex-path /path/to/bin

AFTERWARDS
  Open a new terminal, then:   paperdiff --help
  Verify everything:           ./verify.sh
  Undo everything:             ./uninstall.sh
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRYRUN=1; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --prefix) TL_PREFIX="$2"; shift 2 ;;
    --no-docs) TL_DOCS=0; shift ;;
    --tools-only) DO_TEXLIVE=0; DO_VSCODE=0; DO_TOOLS=1; shift ;;
    --tex-path) TEX_PATH_OPT="$2"; shift 2 ;;
    --skip-texlive) DO_TEXLIVE=0; shift ;;
    --skip-vscode) DO_VSCODE=0; shift ;;
    --skip-tools) DO_TOOLS=0; shift ;;
    --minimal) TL_MINIMAL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "install.sh: unknown option '$1' (try --help)" >&2; exit 2 ;;
  esac
done

export DRYRUN ASSUME_YES

# shellcheck source=lib/common.sh
. "$REPO_DIR/lib/common.sh"    || { echo "cannot load lib/common.sh"; exit 1; }
. "$REPO_DIR/lib/10-texlive.sh" || die "cannot load lib/10-texlive.sh"
. "$REPO_DIR/lib/20-vscode.sh"  || die "cannot load lib/20-vscode.sh"
. "$REPO_DIR/lib/30-tools.sh"   || die "cannot load lib/30-tools.sh"

# --------------------------------------------------------------- banner ----
printf '%s\n' "$C_BOLD"
cat <<'EOF'
  latex-tools
  TeX Live + VS Code LaTeX Workshop + paperdiff
EOF
printf '%s' "$C_0"

OSNAME=$(detect_os)
ARCH=$(detect_arch)
[ "$OSNAME" = "unsupported" ] && die "this installer supports macOS and Linux only (found $(uname -s))"

PYBIN=$(pick_python 2>/dev/null || true)

step "This machine"
info "os          : $OSNAME ($(uname -sr 2>/dev/null))"
info "arch        : $ARCH"
info "tex platform: $(guess_tl_platform)"
info "shell       : ${SHELL:-unknown}"
info "python      : ${PYBIN:-none found}"
info "prefix      : $TL_PREFIX"
info "log         : $LOGFILE"
[ "$DRYRUN" = "1" ] && warn "DRY RUN - nothing will be changed"

have perl || warn "perl not found: TeX Live's installer needs it (macOS ships it; on Linux install 'perl')"
have tar  || die "tar is required but was not found"
if ! have curl && ! have wget; then die "either curl or wget is required to download TeX Live"; fi

# ----------------------------------------------------------------- work ----
export TEX_PATH_OPT
if [ "$DO_TEXLIVE" = "1" ]; then
  install_texlive
else
  step "LaTeX"
  # Not installing TeX Live: use what is already here, and make sure it can
  # actually run the tools before we promise the user anything.
  TL_BIN=$(find_tex_bin 2>/dev/null || true)
  if [ -n "$TL_BIN" ]; then
    info "found: $TL_BIN"
    info "$("$TL_BIN/pdflatex" --version 2>/dev/null | head -1)"
  fi
  if [ "$DO_TOOLS" = "1" ]; then
    if require_tex "$TL_BIN"; then
      ok "this LaTeX can run paperdiff and paperflat"
    else
      exit 1
    fi
  else
    [ -n "$TL_BIN" ] || warn "no LaTeX found"
  fi
fi
# Always run: ~/.local/bin (where the tools live) must go on PATH even when
# TeX Live was skipped or is already installed system-wide.
configure_texlive_path
# Record where TeX is, so the tools work when launched from a GUI too.
write_tex_config "${TL_BIN:-}"

# Make the freshly installed tools visible to the rest of this script.
if [ -n "${TL_BIN:-}" ]; then
  case ":$PATH:" in *":$TL_BIN:"*) ;; *) PATH="$PATH:$TL_BIN"; export PATH ;; esac
fi

if [ "$DO_VSCODE" = "1" ]; then install_vscode_bits; else step "VS Code"; skip "skipped on request"; fi
if [ "$DO_TOOLS" = "1" ]; then install_tools; else step "Command-line tools"; skip "skipped on request"; fi

# -------------------------------------------------------------- summary ----
step "Summary"
if [ -n "${TL_BIN:-}" ] && [ -x "$TL_BIN/pdflatex" ]; then
  ok "TeX Live      $("$TL_BIN/pdflatex" --version 2>/dev/null | head -1)"
else
  warn "TeX Live      not verified"
fi
if [ -x "$HOME/.local/bin/paperdiff" ]; then ok "paperdiff     $HOME/.local/bin/paperdiff"
else warn "paperdiff     not installed"; fi
if [ -n "${VSCODE_CLI:-}" ]; then ok "VS Code       $VSCODE_CLI"
else warn "VS Code       not found - install it, then re-run with --skip-texlive"; fi

cat <<EOF

  ${C_BOLD}Next steps${C_0}
    1. Open a NEW terminal window (so the PATH change takes effect).
    2. Check everything:      $REPO_DIR/verify.sh
    3. Try it:                paperdiff --help
    4. In VS Code, open a .tex file and press Cmd+Alt+B to build.

  Log:      $LOGFILE
  Undo all: $REPO_DIR/uninstall.sh

EOF
exit 0
