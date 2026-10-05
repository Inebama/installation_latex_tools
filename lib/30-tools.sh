# shellcheck shell=bash
# 30-tools.sh — install the command-line tools (currently: paperdiff).

TOOLS_DIR="$HOME/.local/bin"

install_tools() {
  step "Command-line tools"

  mkdir -p "$TOOLS_DIR" 2>/dev/null || die "cannot create $TOOLS_DIR"

  local src dst name
  for src in "$REPO_DIR"/bin/*; do
    [ -f "$src" ] || continue
    name=$(basename "$src")
    dst="$TOOLS_DIR/$name"

    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
      skip "$name already up to date"
      continue
    fi
    if [ -f "$dst" ]; then
      info "$name exists and differs - backing up before replacing"
      backup_file "$dst"
    fi
    if [ "$DRYRUN" = "1" ]; then
      info "[dry-run] would install $name to $dst"
      continue
    fi
    cp "$src" "$dst" || { err "could not install $name"; continue; }
    chmod +x "$dst"
    record "tool|$dst"
    ok "installed $name -> $dst"
  done

  # ---- dependency report -------------------------------------------------
  if [ -n "$PYBIN" ]; then
    if "$PYBIN" -c 'import PIL, numpy' >/dev/null 2>&1; then
      ok "python with Pillow + numpy: $PYBIN (figure comparison fully enabled)"
    else
      warn "python found ($PYBIN) but without Pillow/numpy"
      info "paperdiff still reports added/removed/changed figures (by checksum),"
      info "but pixel statistics and --images need them. To enable:"
      info "    $PYBIN -m pip install --user pillow numpy"
    fi
  else
    warn "no python found: paperdiff will skip the figure comparison entirely"
  fi

  # ---- PATH --------------------------------------------------------------
  case ":$PATH:" in
    *":$TOOLS_DIR:"*) ok "$TOOLS_DIR is already on PATH" ;;
    *) info "$TOOLS_DIR will be added to PATH by the shell block written earlier" ;;
  esac

  # Smoke-test every tool we installed, not just one of them.
  if [ "$DRYRUN" != "1" ]; then
    for src in "$REPO_DIR"/bin/*; do
      [ -f "$src" ] || continue
      name=$(basename "$src")
      [ -x "$TOOLS_DIR/$name" ] || continue
      if "$TOOLS_DIR/$name" --help >/dev/null 2>&1; then
        ok "$name runs correctly"
      else
        warn "$name was installed but did not run cleanly"
      fi
    done
  fi
  return 0
}
