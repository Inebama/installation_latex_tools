#!/usr/bin/env bash
#
# uninstall.sh — reverse exactly what install.sh did, using the manifest it
# wrote. Anything that was already on the machine before is left alone.

set -uo pipefail
REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
LOGFILE=""
. "$REPO_DIR/lib/common.sh"

MANIFEST="${MANIFEST:-$HOME/.latex-tools-manifest}"
KEEP_TEXLIVE=0
ASSUME_YES=0
DRYRUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --keep-texlive) KEEP_TEXLIVE=1; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --dry-run) DRYRUN=1; shift ;;
    -h|--help)
      cat <<'EOF'
uninstall.sh — undo a latex-tools installation

  --keep-texlive   remove the tools and settings but keep TeX Live itself
  --dry-run        list what would be removed, remove nothing
  --yes            do not ask for confirmation
EOF
      exit 0 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
export DRYRUN ASSUME_YES

printf '%s\n  latex-tools — uninstall%s\n' "$C_BOLD" "$C_0"

if [ ! -f "$MANIFEST" ]; then
  warn "no manifest at $MANIFEST"
  info "Nothing recorded, so nothing is removed automatically."
  info "If you want to remove things by hand, they are:"
  info "    ~/texlive  ~/.texlive*  ~/.local/bin/paperdiff"
  info "    plus the '# >>> latex-tools >>>' block in ~/.bash_profile / ~/.zshrc"
  exit 0
fi

step "What will be removed"
TEX_DIRS=$(grep '^texlive|' "$MANIFEST" 2>/dev/null | cut -d'|' -f2 | sort -u)
TOOLS=$(grep '^tool|' "$MANIFEST" 2>/dev/null | cut -d'|' -f2 | sort -u)
BLOCKS=$(grep '^block|' "$MANIFEST" 2>/dev/null | cut -d'|' -f2 | sort -u)
BACKUPS=$(grep '^backup|' "$MANIFEST" 2>/dev/null)

[ "$KEEP_TEXLIVE" = "0" ] && [ -n "$TEX_DIRS" ] && { info "TeX Live:"; echo "$TEX_DIRS" | sed 's/^/        /'; }
[ -n "$TOOLS" ] && { info "tools:"; echo "$TOOLS" | sed 's/^/        /'; }
[ -n "$BLOCKS" ] && { info "shell blocks in:"; echo "$BLOCKS" | sed 's/^/        /'; }

confirm "proceed?" || { info "cancelled"; exit 0; }

# ---- tools ---------------------------------------------------------------
step "Removing tools"
for t in $TOOLS; do
  if [ ! -e "$t" ]; then skip "$t already gone"; continue; fi
  if [ "$DRYRUN" = "1" ]; then info "[dry-run] would remove $t"; continue; fi
  rm -f "$t" && ok "removed $t"
done

# ---- shell blocks --------------------------------------------------------
step "Cleaning shell startup files"
for f in $BLOCKS; do
  [ -f "$f" ] || { skip "$f gone"; continue; }
  if ! grep -qF "$BEGIN_MARK" "$f"; then skip "no block in $f"; continue; fi
  if [ "$DRYRUN" = "1" ]; then info "[dry-run] would strip the block from $f"; continue; fi
  cp -p "$f" "$f.pre-uninstall-$(date +%Y%m%d-%H%M%S)"
  # Blank lines are buffered so that the single blank line the installer put
  # in front of its block is removed with it, leaving the file byte-identical
  # to what it was before installation.
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    function flush(  i){ for(i=0;i<nb;i++) print ""; nb=0 }
    index($0,b){ if(nb>0) nb--; flush(); skip=1; next }
    skip       { if(index($0,e)) skip=0; next }
    /^[ \t]*$/ { nb++; next }
               { flush(); print }
    END        { flush() }' "$f" > "$f.tmp$$" && mv "$f.tmp$$" "$f"
  ok "cleaned $f"
done

# ---- TeX Live ------------------------------------------------------------
if [ "$KEEP_TEXLIVE" = "0" ]; then
  step "Removing TeX Live"
  for d in $TEX_DIRS; do
    if [ ! -d "$d" ]; then skip "$d already gone"; continue; fi
    info "$d ($(du -sh "$d" 2>/dev/null | cut -f1))"
    if [ "$DRYRUN" = "1" ]; then info "[dry-run] would remove it"; continue; fi
    rm -rf "$d" && ok "removed $d"
  done
  for d in "$HOME"/.texlive[0-9]*; do
    [ -d "$d" ] || continue
    if [ "$DRYRUN" = "1" ]; then info "[dry-run] would remove $d"; continue; fi
    rm -rf "$d" && ok "removed $d"
  done
  if [ "$DRYRUN" != "1" ] && [ -d "$HOME/texlive" ]; then
    # texmf-local is ours too, but only delete it if you never put anything there
    if [ -d "$HOME/texlive/texmf-local" ] && [ -z "$(ls -A "$HOME/texlive/texmf-local" 2>/dev/null)" ]; then
      rm -rf "$HOME/texlive/texmf-local"
    fi
    if rmdir "$HOME/texlive" 2>/dev/null; then
      ok "removed $HOME/texlive"
    else
      warn "$HOME/texlive still contains files, so it was kept:"
      ls -A "$HOME/texlive" 2>/dev/null | sed 's/^/        /'
    fi
  fi
else
  step "TeX Live"; skip "kept on request"
fi

# ---- recorded TeX path ---------------------------------------------------
step "Recorded TeX path"
for c in $(grep '^config|' "$MANIFEST" 2>/dev/null | cut -d'|' -f2 | sort -u); do
  if [ ! -e "$c" ]; then skip "$c already gone"; continue; fi
  if [ "$DRYRUN" = "1" ]; then info "[dry-run] would remove $c"; continue; fi
  rm -f "$c" && ok "removed $c"
  rmdir "$(dirname "$c")" 2>/dev/null
done

# ---- VS Code settings ----------------------------------------------------
step "VS Code settings"
info "Your settings.json was backed up before we touched it. To restore:"
echo "$BACKUPS" | grep 'settings.json' | while IFS='|' read -r _ b orig; do
  [ -n "$b" ] && info "cp \"$b\" \"$orig\""
done
info "(the LaTeX Workshop extension itself was left installed)"

# ---- done ----------------------------------------------------------------
if [ "$DRYRUN" != "1" ]; then
  mv "$MANIFEST" "$MANIFEST.removed-$(date +%Y%m%d-%H%M%S)" 2>/dev/null
fi
step "Done"
info "Open a new terminal for the PATH change to take effect."
exit 0
