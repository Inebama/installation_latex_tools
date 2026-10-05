#!/usr/bin/env bash
#
# verify.sh — check that everything latex-tools installs is actually working.
# Read-only: it never changes anything. Exit code 0 = all good.

set -uo pipefail
REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
LOGFILE=""
. "$REPO_DIR/lib/common.sh"
. "$REPO_DIR/lib/20-vscode.sh"   # for vscode_find_cli / vscode_settings_path

PASS=0; FAIL=0; WARNN=0
chk_ok()   { ok "$*";   PASS=$((PASS+1)); }
chk_bad()  { err "$*";  FAIL=$((FAIL+1)); }
chk_warn() { warn "$*"; WARNN=$((WARNN+1)); }

printf '%s\n  latex-tools — verification%s\n' "$C_BOLD" "$C_0"

# ------------------------------------------------------------- machine ----
step "Machine"
info "os   : $(detect_os) / $(detect_arch)"
info "shell: ${SHELL:-unknown}"

# ------------------------------------------------------------ TeX Live ----
step "TeX Live"
TLB=""
if command -v pdflatex >/dev/null 2>&1; then
  TLB=$(dirname "$(command -v pdflatex)")
else
  for d in "$HOME"/texlive/*/bin/*; do [ -x "$d/pdflatex" ] && TLB="$d" && break; done
fi

if [ -z "$TLB" ]; then
  chk_bad "pdflatex not found (open a NEW terminal, or re-run install.sh)"
else
  chk_ok "pdflatex: $TLB/pdflatex"
  info "$("$TLB/pdflatex" --version 2>/dev/null | head -1)"
  for t in latexmk bibtex biber latexdiff xelatex lualatex tlmgr texdoc; do
    if [ -x "$TLB/$t" ]; then chk_ok "$t"; else chk_bad "$t is missing"; fi
  done

  # languages actually compiled into the format
  if [ -x "$TLB/kpsewhich" ]; then
    LD=$("$TLB/kpsewhich" language.dat 2>/dev/null)
    if [ -n "$LD" ] && [ -f "$LD" ]; then
      LANGS=$(grep -vE '^\s*(%|$)' "$LD" | awk '{print $1}' | sort -u | tr '\n' ' ')
      info "hyphenation: $LANGS"
      for want in english spanish french italian portuguese; do
        case " $LANGS " in
          *" $want "*) chk_ok "hyphenation: $want" ;;
          *) chk_warn "hyphenation pattern '$want' not found" ;;
        esac
      done
    fi
  fi

  # a real end-to-end compile, bibtex included
  T=$(mktemp -d 2>/dev/null || mktemp -d -t ltv)
  cat > "$T/t.tex" <<'EOF'
\documentclass{article}
\usepackage[T1]{fontenc}\usepackage{amsmath,graphicx,hyperref,natbib,booktabs,siunitx}
\begin{document}Test \SI{5}{\metre} $\alpha$ \citep{k}
\bibliographystyle{plainnat}\bibliography{b}\end{document}
EOF
  cat > "$T/b.bib" <<'EOF'
@article{k, author={A. Author}, title={T}, journal={J}, year={2020}}
EOF
  ( cd "$T" && "$TLB/pdflatex" -interaction=nonstopmode t.tex >o1 2>&1 \
      && "$TLB/bibtex" t >o2 2>&1 \
      && "$TLB/pdflatex" -interaction=nonstopmode t.tex >o3 2>&1 \
      && "$TLB/pdflatex" -interaction=nonstopmode t.tex >o4 2>&1 )
  if [ -s "$T/t.pdf" ] && ! grep -q 'Citation.*undefined' "$T/t.log" 2>/dev/null; then
    chk_ok "full build works (pdflatex + bibtex + citations resolve)"
  else
    chk_bad "the end-to-end test build failed"
    [ -f "$T/t.log" ] && grep -E '^!' -A3 "$T/t.log" | head -10 | sed 's/^/        /'
  fi
  rm -rf "$T"
fi

# ------------------------------------------------------------ paperdiff ----
step "Command-line tools"
for t in $(ls "$REPO_DIR/bin" 2>/dev/null); do
  if command -v "$t" >/dev/null 2>&1; then
    chk_ok "$t on PATH: $(command -v "$t")"
    if "$t" --help >/dev/null 2>&1; then chk_ok "$t runs"; else chk_bad "$t does not run"; fi
  elif [ -x "$HOME/.local/bin/$t" ]; then
    chk_warn "$t is installed but NOT on PATH (open a new terminal)"
  else
    chk_bad "$t is not installed"
  fi
done
# latexpand is what paperflat relies on
if command -v latexpand >/dev/null 2>&1; then chk_ok "latexpand (needed by paperflat)"; else chk_bad "latexpand missing"; fi

PY=$(pick_python 2>/dev/null || true)
if [ -n "$PY" ]; then
  if "$PY" -c 'import PIL, numpy' >/dev/null 2>&1; then
    chk_ok "python with Pillow+numpy: $PY (figure comparison enabled)"
  else
    chk_warn "python $PY lacks Pillow/numpy - figure pixel stats disabled"
  fi
else
  chk_warn "no python found - paperdiff figure comparison disabled"
fi

# -------------------------------------------------------------- VS Code ----
step "VS Code"
CLI=$(vscode_find_cli 2>/dev/null || true)
if [ -z "$CLI" ]; then
  chk_warn "VS Code not found (only needed if you want to edit LaTeX there)"
else
  chk_ok "VS Code: $CLI"
  if "$CLI" --list-extensions 2>/dev/null | grep -qi '^james-yu.latex-workshop$'; then
    chk_ok "LaTeX Workshop extension installed"
  else
    chk_bad "LaTeX Workshop extension is NOT installed"
  fi
  SJ=$(vscode_settings_path)
  if [ -f "$SJ" ]; then
    if grep -q 'latex-workshop.latex.tools' "$SJ" 2>/dev/null; then
      chk_ok "build recipes configured in settings.json"
      if [ -n "$TLB" ] && grep -q "$TLB" "$SJ" 2>/dev/null; then
        chk_ok "recipes point at $TLB"
      else
        chk_warn "recipes do not mention $TLB - re-run install.sh"
      fi
    else
      chk_bad "settings.json has no LaTeX Workshop configuration"
    fi
  else
    chk_warn "no settings.json yet at $SJ"
  fi
fi

# -------------------------------------------------------------- summary ----
step "Result"
printf '      %s%d passed%s, %s%d warnings%s, %s%d failed%s\n' \
  "$C_G" "$PASS" "$C_0" "$C_Y" "$WARNN" "$C_0" "$C_R" "$FAIL" "$C_0"
if [ "$FAIL" -eq 0 ]; then
  printf '\n      Everything works. Try:  %spaperdiff --help%s\n\n' "$C_BOLD" "$C_0"
  exit 0
fi
printf '\n      Re-run %s%s/install.sh%s to repair.\n\n' "$C_BOLD" "$REPO_DIR" "$C_0"
exit 1
