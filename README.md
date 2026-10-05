# latex-tools

Set up a complete LaTeX working environment on a new Mac or Linux machine with
one command: TeX Live, VS Code's LaTeX Workshop wired to it, and two commands
for writing papers — **`paperdiff`**, which shows what changed between two
versions, and **`paperflat`**, which puts all the writing into a single `.tex`
for journal submission.

**The only thing you need beforehand is VS Code** — and even that is optional;
everything else installs regardless, and you can re-run the installer later.

---

## Two ways to install

**Everything** (TeX Live + VS Code + the tools) — for a brand-new machine:

```bash
./install.sh
```

**Just the two commands**, using the LaTeX you already have — if the machine
already has MacTeX, TeX Live or a distro LaTeX and you only want `paperdiff`
and `paperflat`:

```bash
./install.sh --tools-only
```

That touches nothing but `~/.local/bin`. It first checks your LaTeX can
actually run them (`pdflatex`, `latexmk`, `latexdiff`, `bibtex`) and stops
with a one-line explanation if it cannot. If your LaTeX is somewhere unusual:

```bash
./install.sh --tools-only --tex-path /usr/local/texlive/2025/bin/universal-darwin
```

---

## Install on a new laptop

```bash
git clone https://github.com/Inebama/installation_latex_tools.git
cd installation_latex_tools
./install.sh
```

Or, without git: copy the folder across and **double-click `Install.command`**
in Finder — macOS opens it in Terminal and runs the same thing.

Then **open a new terminal window** (so the PATH change takes effect) and check:

```bash
./verify.sh
```

It takes 20–40 minutes, almost all of it downloading TeX Live (~9 GB installed).

To update an existing machine later:

```bash
git pull && ./install.sh
```

Re-running is safe — anything already installed and working is left alone.

---

## What you get

| | |
|---|---|
| **TeX Live** | `~/texlive/<year>`, installed **without `sudo`**. Every package (all 29 non-language collections: latexextra, fontsextra, mathscience, publishers, pstricks, bibtexextra, luatex, xetex, ConTeXt…) plus documentation, so `texdoc siunitx` works offline. |
| **Languages** | English, Spanish, French, Italian, Portuguese, Japanese only. Arabic, Chinese, Cyrillic, Czech, German, Greek, Korean, Polish and "other European" are deliberately left out. |
| **VS Code** | LaTeX Workshop extension, plus build recipes whose `PATH` points at this TeX Live explicitly — so builds work even when VS Code doesn't inherit your shell environment. `Cmd+Alt+B` builds, `Cmd+Alt+V` views. |
| **paperdiff** | `~/.local/bin/paperdiff` — shows what changed between two versions of a paper: text, references, figures and tables. [Details below](#paperdiff--what-changed-between-two-versions). |
| **paperflat** | `~/.local/bin/paperflat` — puts all the writing into **one `.tex`** for journals that demand a single source file. [Details below](#paperflat--one-tex-with-all-the-writing). |

If a language you skipped is ever needed:

```bash
tlmgr install collection-langgerman
```

---

## paperdiff — what changed between two versions

Point it at two copies of the paper, oldest first:

```bash
paperdiff ~/Downloads/paper_submitted ~/Downloads/paper_current
```

About 30 s later you have `./paperdiff-out/` containing `diff.pdf`: your paper
with **added or replaced text in green (`#00CF39`)** and **deleted text struck
through in red**. It handles a nested `\input{}` layout without touching your
files, and neither source directory is ever modified.

### What it compares

| | |
|---|---|
| **Text** | Word-level, through the whole paper including appendices. |
| **References** | It builds each version's `.bbl` first, so the reference list itself is marked up — new entries in green, and an entry that changed (say `arXiv:2506.11278` → `A&A, 700, A213`) shown both ways. Skip with `--no-bib` if you want speed. |
| **Figures** | `figures-report.txt`: added, removed, modified. Changed images get per-pixel statistics; `--images` writes `old \| new \| red heat-map` composites to `figure-diffs/`. |
| **Tables** | `tables-report.txt` — see the warning below. |

### Read `tables-report.txt`, always

`latexdiff` **cannot mark up changes inside a `tabular`**, because `&` and `\\`
are alignment syntax — it turns deleted table rows into invisible
`%DIFDELCMD` comments, so the old table vanishes from the PDF and the new one
appears unmarked, with nothing to tell you it changed.

So `paperdiff` compares tables itself and writes them to a separate file,
pairing tables by `\label` and reporting the column spec, the header row and
the row count:

```
~ tab:targets   "Targets main parameters."
    header row  -  N & Star ID & RA (deg) & DEC (deg) & $I_0$ [mag] & ...
                +  N & Star ID & PoP & Class & $I_0$ [mag] & ...
    data rows   :  56 rows, 112 line changes
```

The console prints `^ none of the above is visible in diff.pdf` when this
applies, so you cannot miss it. **The PDF alone is complete for prose and
references, but silently incomplete for tables.**

### Colours

```bash
paperdiff old new --new-color teal --old-color 'B00020'
```

Any 6-digit hex (`00CF39`, `'#00CF39'` — quote it, `#` starts a comment in
bash), 3-digit shorthand, one of xcolor's 19 names, or a blend like `red!60`.
An unusable colour stops the run immediately with the valid options listed,
rather than failing deep inside a LaTeX log.

Green is the default for additions because `latexdiff`'s own blue is the same
blue as A&A citation links, which makes new text and references impossible to
tell apart.

### Other options

```bash
paperdiff old new --figures-only          # skip the LaTeX diff (~1 s)
paperdiff old new --images --open         # figure composites, then open the PDF
paperdiff old new -o ~/Desktop/referee    # choose the output directory
paperdiff old new -m paper.tex            # if the main file can't be guessed
```

If the diff fails to compile — almost always a table or an equation — try
`--math whole`, then `--ld --disable-citation-markup`. Those are the two usual
`latexdiff` culprits, and the script prints that hint on failure.

---

## paperflat — one .tex with all the writing

Journals and language editors often want a single source file. If your paper is
split across `Sections/*.tex`, run this in the paper's folder:

```bash
paperflat
```

It replaces every `\input{}` between `\begin{document}` and `\end{document}`
with the contents of that file, recursively — **and nothing else**:

* your comments are kept exactly as written
* a commented-out `\input` stays a comment and is *not* expanded
* the preamble and `\bibliography{}` are left alone
* spacing and blank lines are untouched; included files appear verbatim

Your own files are never modified; the result is `<main>-flat.tex`.

**It proves the result rather than assuming it** — the flattened file is
compiled and compared with your original PDF, page by page:

```
    24 \input/\include expanded
    1 commented-out \input left as comments (not expanded)
    flattened: 22 pages (original: 22)
    all 22 pages are textually IDENTICAL to the original
```

If one word moved, it names the page and shows the difference.

Two opt-in extras, when you want a file that stands completely alone:

```bash
paperflat --preamble      # expand \input{} in the preamble too
paperflat --bbl           # inline the reference list from the .bbl
```

And if you also need the figures gathered, `--bundle` collects the figures and
style files the paper *actually* uses — read from the `.fls` recorder of a real
compile, so it is exactly what LaTeX read:

```bash
paperflat --bundle --flat-figures --zip
```

`--flat-figures` puts every figure in one directory, folding the folder into
each filename. That matters: in a real paper
`Figures/apendix_stellar_params/Figure_1.png` and
`Figures/appendix_data_software/cont_example/Figure_1.png` both exist, and a
naive flatten would silently destroy seven figures.

---

## Safety

This installer is built to be run on a machine you care about.

* **No `sudo`, ever.** Nothing outside your home directory is touched. A
  password prompt is the most common way an unattended install dies.
* **Re-running is safe.** Anything already installed and working is detected
  and left alone. Running it twice changes nothing the second time.
* **Your PATH is appended, never prepended**, so this can't shadow Homebrew,
  MacPorts or conda tools you already rely on.
* **Every file it edits is backed up first** (`*.latex-tools-backup-<date>`),
  and every change is written to `~/.latex-tools-manifest`.
* **An existing system TeX Live** (MacTeX in `/usr/local/texlive`, or a
  distro package) is detected and left completely alone.
* **Your VS Code settings are merged, not replaced.** Every key you already
  have is preserved. If the file can't be parsed it is not touched at all.
* **`--dry-run`** shows exactly what would happen and changes nothing.

```bash
./install.sh --dry-run      # see what it would do
./uninstall.sh              # undo it all
./uninstall.sh --keep-texlive
```

---

## Options

```
--dry-run         show what would be done; change nothing
--yes             never ask questions (unattended)
--prefix DIR      where TeX Live goes            (default ~/texlive)
--no-docs         skip package docs (smaller, but no `texdoc`)
--tools-only      install only paperdiff and paperflat, using existing LaTeX
--tex-path DIR    where your LaTeX is, if not found automatically
--skip-texlive    don't touch TeX Live (e.g. you already have MacTeX)
--skip-vscode     don't touch VS Code
--skip-tools      don't install paperdiff
--minimal         tiny TeX Live — for testing this script only
```

---

## If something goes wrong

Everything is logged to `logs/install-<date>.log`.

| Symptom | Fix |
|---|---|
| `No LaTeX found on this machine` | Point at it with `--tex-path DIR`, or run `./install.sh` to install TeX Live. |
| `cannot run these tools / missing: latexdiff` | `tlmgr install latexdiff`, or `./install.sh` for a complete TeX Live. |
| `paperdiff: command not found` | Open a **new** terminal. If it persists, `./verify.sh`. |
| A table changed but the diff PDF doesn't show it | Expected — `latexdiff` cannot mark up `tabular`. Read `tables-report.txt`. |
| The diff PDF fails to compile | `--math whole`, then `--ld --disable-citation-markup`. |
| Download fails | It tries 7 CTAN mirrors in turn. If all fail it's your network/proxy. |
| VS Code not found | Install VS Code, then `./install.sh --skip-texlive`. |
| Builds work in the terminal but not in VS Code | `./install.sh --skip-texlive` rewrites the recipes with the correct path. |
| Figure comparison disabled | Install Pillow and numpy: `python3 -m pip install --user pillow numpy`. |
| Want it all gone | `./uninstall.sh` |

---

## Platform support

Tested on macOS (Apple Silicon). Written to work on Intel Macs and on Linux
(x86-64 and ARM) too: the TeX Live platform, VS Code location, settings path
and shell files are all detected at run time, nothing is hardcoded.

`paperdiff` and `paperflat` locate LaTeX at run time with no hardcoded year or
architecture: whatever is on `PATH` wins, then the path the installer recorded
in `~/.config/latex-tools/config`, then the usual places
(`~/texlive/*/bin/*`, `/usr/local/texlive/*/bin/*`, `/Library/TeX/texbin`,
Homebrew, MacPorts). That last fallback is what makes them work when launched
from Finder or VS Code, whose `PATH` often lacks TeX.

The shell scripts are deliberately **bash 3.2 compatible**, because that is
what macOS still ships — a script using associative arrays or `readarray`
would fail on a brand-new Mac.

---

## Layout

```
install.sh          main installer
Install.command     double-clickable wrapper for Finder
verify.sh           read-only health check
uninstall.sh        undo, using the manifest
bin/paperdiff       show what changed between two versions of a paper
bin/paperflat       put all the writing into one .tex
lib/common.sh       logging, detection, downloads, backups
lib/10-texlive.sh   TeX Live
lib/20-vscode.sh    extension + settings merge
lib/30-tools.sh     command-line tools
doc/                VS Code settings, for manual use
logs/               install logs
```

To add another tool later, drop it into `bin/` — `install.sh` installs
everything it finds there.
