# shellcheck shell=bash
# 20-vscode.sh — install the LaTeX Workshop extension and wire it to our TeX.
#
# The one thing we cannot do for the user is install VS Code itself, so this
# module is written to fail *softly*: if VS Code is missing, everything else
# still gets installed and we say exactly what to do afterwards.

vscode_find_cli() {
  # Echo a usable VS Code CLI path, or nothing. Sets VSC_FLAVOUR as a side effect.
  local c
  for c in code code-insiders codium; do
    if have "$c"; then
      VSC_FLAVOUR="$c"
      command -v "$c"
      return 0
    fi
  done
  # Not on PATH (normal on macOS, where the CLI is inside the .app bundle)
  local p
  for p in \
    "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" \
    "$HOME/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" \
    "/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/bin/code-insiders" \
    "/Applications/VSCodium.app/Contents/Resources/app/bin/codium" \
    "$HOME/Applications/VSCodium.app/Contents/Resources/app/bin/codium" \
    "/usr/share/code/bin/code" "/usr/bin/code" "/snap/bin/code" \
    "/var/lib/flatpak/exports/bin/com.visualstudio.code" \
    "$HOME/.local/share/flatpak/exports/bin/com.visualstudio.code"; do
    if [ -x "$p" ]; then
      case "$p" in
        *Insiders*) VSC_FLAVOUR="code-insiders" ;;
        *odium*)    VSC_FLAVOUR="codium" ;;
        *)          VSC_FLAVOUR="code" ;;
      esac
      echo "$p"
      return 0
    fi
  done
  return 1
}

vscode_settings_path() {
  local base
  case "$(detect_os)" in
    macos) base="$HOME/Library/Application Support" ;;
    *)     base="${XDG_CONFIG_HOME:-$HOME/.config}" ;;
  esac
  case "${VSC_FLAVOUR:-code}" in
    code-insiders) echo "$base/Code - Insiders/User/settings.json" ;;
    codium)        echo "$base/VSCodium/User/settings.json" ;;
    *)             echo "$base/Code/User/settings.json" ;;
  esac
}

install_vscode_bits() {
  step "VS Code"

  local cli
  cli=$(vscode_find_cli 2>/dev/null || true)
  if [ -z "$cli" ]; then
    warn "VS Code not found on this machine."
    info "Install it from https://code.visualstudio.com/ and then re-run:"
    info "    $REPO_DIR/install.sh --skip-texlive"
    VSCODE_OK=0
    return 0
  fi
  ok "found: $cli"
  VSCODE_CLI="$cli"

  # ---- extension ---------------------------------------------------------
  local ext="james-yu.latex-workshop" have_ext=0
  if "$cli" --list-extensions 2>/dev/null | grep -qi "^$ext$"; then have_ext=1; fi
  if [ "$have_ext" = "1" ]; then
    skip "LaTeX Workshop already installed"
  else
    info "installing the LaTeX Workshop extension..."
    if run "$cli" --install-extension "$ext" --force >/dev/null 2>&1; then
      ok "LaTeX Workshop installed"
      record "vscode-ext|$ext"
    else
      warn "could not install the extension automatically"
      info "install it by hand: VS Code -> Extensions -> search 'LaTeX Workshop'"
    fi
  fi

  # ---- settings ----------------------------------------------------------
  local sj
  sj=$(vscode_settings_path)
  info "settings file: $sj"

  if [ -z "$PYBIN" ]; then
    warn "no python found, so settings cannot be merged automatically"
    info "add these keys to $sj by hand (see doc/vscode-settings.json in this repo)"
    return 0
  fi
  if [ -z "${TL_BIN:-}" ]; then
    warn "TeX Live bin directory unknown - skipping the settings merge"
    return 0
  fi

  [ "$DRYRUN" = "1" ] || mkdir -p "$(dirname "$sj")" 2>/dev/null

  # The backup is made by the python below, and only when it is actually going
  # to write, so an already-correct machine collects no stray backup files.
  local msg rc bak
  msg=$("$PYBIN" - "$sj" "$TL_BIN" "$DRYRUN" <<'PYSET'
import json, os, re, sys
path, texbin = sys.argv[1], sys.argv[2]
dry = len(sys.argv) > 3 and sys.argv[3] == "1"

def strip_jsonc(s):
    """Remove // and /* */ comments and trailing commas, respecting strings."""
    out, i, n = [], 0, len(s)
    instr = esc = False
    while i < n:
        c = s[i]
        if instr:
            out.append(c)
            if esc:            esc = False
            elif c == '\\':    esc = True
            elif c == '"':     instr = False
            i += 1
            continue
        if c == '"':
            instr = True; out.append(c); i += 1; continue
        if c == '/' and i + 1 < n and s[i+1] == '/':
            while i < n and s[i] != '\n': i += 1
            continue
        if c == '/' and i + 1 < n and s[i+1] == '*':
            i += 2
            while i + 1 < n and not (s[i] == '*' and s[i+1] == '/'): i += 1
            i += 2
            continue
        out.append(c); i += 1
    t = ''.join(out)
    return re.sub(r',(\s*[}\]])', r'\1', t)

raw, had_comments = "", False
if os.path.exists(path):
    raw = open(path, encoding='utf-8-sig', errors='replace').read()
try:
    cur = json.loads(raw) if raw.strip() else {}
except Exception:
    stripped = strip_jsonc(raw)
    had_comments = stripped != raw
    try:
        cur = json.loads(stripped) if stripped.strip() else {}
    except Exception as e:
        print("SETTINGS-UNPARSEABLE %s" % e)
        sys.exit(9)
if not isinstance(cur, dict):
    print("SETTINGS-NOT-AN-OBJECT"); sys.exit(9)

PATHENV = texbin + ":/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
ENV = {"PATH": PATHENV}
want = {
  "latex-workshop.latex.tools": [
    {"name": "latexmk", "command": "latexmk",
     "args": ["-synctex=1", "-interaction=nonstopmode", "-file-line-error",
              "-pdf", "-outdir=%OUTDIR%", "%DOC%"], "env": ENV},
    {"name": "pdflatex", "command": "pdflatex",
     "args": ["-synctex=1", "-interaction=nonstopmode", "-file-line-error", "%DOC%"],
     "env": ENV},
    {"name": "bibtex", "command": "bibtex", "args": ["%DOCFILE%"], "env": ENV},
  ],
  "latex-workshop.latex.recipes": [
    {"name": "latexmk (recommended)", "tools": ["latexmk"]},
    {"name": "pdflatex -> bibtex -> pdflatex x2",
     "tools": ["pdflatex", "bibtex", "pdflatex", "pdflatex"]},
  ],
  "latex-workshop.view.pdf.viewer": "tab",
  "latex-workshop.latex.autoBuild.run": "onSave",
  "latex-workshop.latex.autoClean.run": "never",
}

changed = [k for k, v in want.items() if cur.get(k) != v]
if not changed:
    print("SETTINGS-ALREADY-CORRECT")
    sys.exit(0)
if dry:
    print("SETTINGS-WOULD-UPDATE %d: %s" % (len(changed), ", ".join(changed)))
    sys.exit(0)

bak = ""
if os.path.exists(path):
    import shutil, time
    bak = path + ".latex-tools-backup-" + time.strftime("%Y%m%d-%H%M%S")
    shutil.copy2(path, bak)

cur.update(want)
tmp = path + ".latex-tools-tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(cur, fh, indent=4, ensure_ascii=False)
    fh.write("\n")
os.replace(tmp, path)
print("SETTINGS-UPDATED %d %s" % (len(changed), "COMMENTS-DROPPED" if had_comments else ""))
if bak:
    print("BACKUP %s" % bak)
PYSET
)
  rc=$?
  case "$msg" in
    SETTINGS-ALREADY-CORRECT*)
        skip "LaTeX Workshop settings already correct - file not touched" ;;
    SETTINGS-WOULD-UPDATE*)
        info "[dry-run] would set: ${msg#SETTINGS-WOULD-UPDATE *: }" ;;
    SETTINGS-UPDATED*)
        ok "settings merged (all your existing settings preserved)"
        record "vscode-settings|$sj"
        case "$msg" in
          *"BACKUP "*)
            bak=$(printf '%s\n' "$msg" | sed -n 's/^BACKUP //p' | head -1)
            [ -n "$bak" ] && { record "backup|$bak|$sj"; info "backup: $(basename "$bak")"; } ;;
        esac
        case "$msg" in
          *COMMENTS-DROPPED*)
            warn "comments in settings.json were removed by the merge (a backup was made)" ;;
        esac ;;
    SETTINGS-UNPARSEABLE*|SETTINGS-NOT-AN-OBJECT*)
        warn "settings.json could not be parsed - it was left completely untouched"
        info "add the keys from doc/vscode-settings.json by hand" ;;
    *)
        [ "$rc" -eq 0 ] || warn "settings merge failed (exit $rc) - file left untouched" ;;
  esac
  return 0
}
