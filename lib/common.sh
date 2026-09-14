# shellcheck shell=bash
# common.sh — shared helpers for the latex-tools installer.
# Deliberately bash 3.2 compatible: macOS ships bash 3.2 and a fresh Mac has
# nothing newer. No associative arrays, no readarray, no ${x^^}.

# ---------------------------------------------------------------- output ----
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_R=$(printf '\033[31m'); C_G=$(printf '\033[32m'); C_Y=$(printf '\033[33m')
  C_B=$(printf '\033[34m'); C_D=$(printf '\033[2m');  C_0=$(printf '\033[0m')
  C_BOLD=$(printf '\033[1m')
else
  C_R=; C_G=; C_Y=; C_B=; C_D=; C_0=; C_BOLD=
fi

LOGFILE="${LOGFILE:-}"
_log() { [ -n "$LOGFILE" ] && printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >> "$LOGFILE"; return 0; }

step()  { printf '\n%s==>%s %s%s%s\n' "$C_B" "$C_0" "$C_BOLD" "$*" "$C_0"; _log "==> $*"; }
info()  { printf '      %s\n' "$*"; _log "    $*"; }
ok()    { printf '      %s+%s %s\n' "$C_G" "$C_0" "$*"; _log "    OK   $*"; }
skip()  { printf '      %s=%s %s\n' "$C_D" "$C_0" "$*"; _log "    SKIP $*"; }
warn()  { printf '      %s!%s %s\n' "$C_Y" "$C_0" "$*"; _log "    WARN $*"; }
err()   { printf '      %sx%s %s\n' "$C_R" "$C_0" "$*" >&2; _log "    ERR  $*"; }
die()   { err "$*"; printf '\n%sInstallation stopped.%s Nothing further was changed.\n' "$C_R" "$C_0" >&2
          [ -n "$LOGFILE" ] && printf 'Full log: %s\n' "$LOGFILE" >&2
          exit 1; }

DRYRUN="${DRYRUN:-0}"
run() {   # run a command, honouring --dry-run
  if [ "$DRYRUN" = "1" ]; then printf '      %s[dry-run]%s %s\n' "$C_D" "$C_0" "$*"; return 0; fi
  _log "RUN $*"
  "$@"
}

# ------------------------------------------------------------ detection ----
detect_os() {
  case "$(uname -s 2>/dev/null)" in
    Darwin) echo macos ;;
    Linux)  echo linux ;;
    *)      echo unsupported ;;
  esac
}

detect_arch() { uname -m 2>/dev/null || echo unknown; }

# TeX Live's own name for this platform. install-tl --print-platform is
# authoritative; this is the fallback used before the installer is unpacked.
guess_tl_platform() {
  local os arch
  os=$(detect_os); arch=$(detect_arch)
  case "$os" in
    macos) echo universal-darwin ;;
    linux)
      case "$arch" in
        x86_64|amd64)  echo x86_64-linux ;;
        aarch64|arm64) echo aarch64-linux ;;
        i?86)          echo i386-linux ;;
        armv7l)        echo armhf-linux ;;
        *)             echo "" ;;
      esac ;;
    *) echo "" ;;
  esac
}

human_size() {  # bytes -> human
  local b="$1"
  if [ "$b" -ge 1073741824 ] 2>/dev/null; then echo "$((b/1073741824)) GB"
  elif [ "$b" -ge 1048576 ] 2>/dev/null; then echo "$((b/1048576)) MB"
  elif [ "$b" -ge 1024 ] 2>/dev/null; then echo "$((b/1024)) KB"
  else echo "${b} B"; fi
}

free_space_mb() {  # free MB on the filesystem holding $1 (or its nearest existing parent)
  local d="$1"
  while [ ! -d "$d" ] && [ "$d" != "/" ]; do d=$(dirname "$d"); done
  df -Pk "$d" 2>/dev/null | awk 'NR==2 {print int($4/1024)}'
}

# ------------------------------------------------------------- download ----
# Ordered CTAN mirrors. mirror.ctan.org redirects to a nearby one; the rest are
# explicit fallbacks in case that redirector is down or blocked.
# (All verified reachable when this file was written.)
CTAN_MIRRORS="
https://mirror.ctan.org/systems/texlive/tlnet
https://ctan.math.illinois.edu/systems/texlive/tlnet
https://mirrors.mit.edu/CTAN/systems/texlive/tlnet
https://mirrors.rit.edu/CTAN/systems/texlive/tlnet
https://ftp.fau.de/ctan/systems/texlive/tlnet
https://mirror.las.iastate.edu/tex-archive/systems/texlive/tlnet
https://ctan.dcc.uchile.cl/systems/texlive/tlnet
"

have() { command -v "$1" >/dev/null 2>&1; }

# fetch URL OUTFILE  — curl first, wget second; retries built in.
fetch() {
  local url="$1" out="$2"
  if have curl; then
    curl -fsSL --connect-timeout 25 --max-time 7200 --retry 3 --retry-delay 2 \
         -o "$out" "$url" 2>/dev/null && [ -s "$out" ] && return 0
  fi
  if have wget; then
    wget -q --timeout=25 --tries=3 -O "$out" "$url" 2>/dev/null && [ -s "$out" ] && return 0
  fi
  rm -f "$out" 2>/dev/null
  return 1
}

# fetch_from_mirrors RELPATH OUTFILE  — try every mirror in turn.
# On success echoes the mirror base that worked (on stdout) and returns 0.
fetch_from_mirrors() {
  local rel="$1" out="$2" m
  for m in $CTAN_MIRRORS; do
    if fetch "$m/$rel" "$out"; then
      echo "$m"
      return 0
    fi
  done
  return 1
}

# ------------------------------------------------- backups / change log ----
# Every file we touch is copied first, and every change is appended to the
# manifest so uninstall.sh can reverse exactly what this installer did.
MANIFEST="${MANIFEST:-$HOME/.latex-tools-manifest}"

record() { [ "$DRYRUN" = "1" ] && return 0; printf '%s\n' "$*" >> "$MANIFEST"; }

backup_file() {  # backup_file PATH   (no-op if the file does not exist)
  local f="$1" b
  [ -f "$f" ] || return 0
  b="$f.latex-tools-backup-$(date +%Y%m%d-%H%M%S)"
  if [ "$DRYRUN" = "1" ]; then
    info "[dry-run] would back up $f"
    return 0
  fi
  cp -p "$f" "$b" || { err "could not back up $f"; return 1; }
  record "backup|$b|$f"
  info "backed up $(basename "$f") -> $(basename "$b")"
  return 0
}

BEGIN_MARK="# >>> latex-tools >>>"
END_MARK="# <<< latex-tools <<<"

# append_block FILE CONTENT_FILE GUARD_STRING
#   Appends the contents of CONTENT_FILE wrapped in markers, but only if
#   neither the marker nor GUARD_STRING is already in the file. GUARD_STRING
#   lets us recognise an equivalent block added by hand or by an earlier tool,
#   so we never create a duplicate PATH entry.
#
#   The block is passed as a *file* rather than a string on purpose: bash 3.2
#   (which is what macOS ships) mis-parses a heredoc inside $( ), and our block
#   contains a `case` statement whose `*)` would be read as the closing paren.
append_block() {
  local f="$1" contentfile="$2" guard="$3"
  if [ -f "$f" ] && grep -qF "$BEGIN_MARK" "$f" 2>/dev/null; then
    skip "$(basename "$f") already has a latex-tools block"
    return 1
  fi
  if [ -n "$guard" ] && [ -f "$f" ] && grep -qF "$guard" "$f" 2>/dev/null; then
    skip "$(basename "$f") already references this path - leaving it alone"
    return 1
  fi
  if [ "$DRYRUN" = "1" ]; then
    info "[dry-run] would append a latex-tools block to $f"
    return 0
  fi
  [ -e "$f" ] || { touch "$f" && record "created|$f"; }
  backup_file "$f"
  {
    printf '\n%s\n' "$BEGIN_MARK"
    cat "$contentfile"
    printf '%s\n' "$END_MARK"
  } >> "$f"
  record "block|$f"
  ok "updated $f"
  return 0
}

# --------------------------------------------------------------- prompts ----
ASSUME_YES="${ASSUME_YES:-0}"
confirm() {  # confirm "question"  -> 0 yes / 1 no
  local q="$1" a
  [ "$ASSUME_YES" = "1" ] && return 0
  if [ ! -t 0 ]; then return 0; fi     # non-interactive: proceed
  printf '      %s?%s %s [Y/n] ' "$C_Y" "$C_0" "$q"
  read -r a || a=""
  case "$a" in [nN]*) return 1 ;; *) return 0 ;; esac
}

# --------------------------------------------------------------- python ----
# Pick the best available python: one that can do the figure comparison
# (Pillow + numpy) if possible, otherwise any python3.
pick_python() {
  local p best=""
  for p in "${PAPERDIFF_PYTHON:-}" \
           "$HOME/miniconda3/bin/python" /opt/miniconda3/bin/python \
           "$HOME/anaconda3/bin/python" /opt/anaconda3/bin/python \
           "$(command -v python3 2>/dev/null)" "$(command -v python 2>/dev/null)"; do
    [ -n "$p" ] && [ -x "$p" ] || continue
    "$p" -c 'import sys; sys.exit(0)' >/dev/null 2>&1 || continue
    if "$p" -c 'import PIL, numpy' >/dev/null 2>&1; then echo "$p"; return 0; fi
    [ -z "$best" ] && best="$p"
  done
  [ -n "$best" ] && { echo "$best"; return 0; }
  return 1
}
