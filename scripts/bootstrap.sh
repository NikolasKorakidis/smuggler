#!/usr/bin/env bash
# Smuggler dev-environment check for macOS.
# Reports what is installed and what is missing. Installs nothing by itself
# unless you pass --install (then uses Homebrew for missing tools).
set -u

INSTALL=0
[[ "${1:-}" == "--install" ]] && INSTALL=1

ok()   { printf "  \033[32m✔\033[0m %s\n" "$1"; }
miss() { printf "  \033[31m✘\033[0m %s\n" "$1"; MISSING+=("$2"); }
MISSING=()

echo "== Machine =="
echo "  macOS $(sw_vers -productVersion), $(uname -m)"
echo "  Chip:  $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
echo "  RAM:   $(( $(sysctl -n hw.memsize) / 1073741824 )) GB"
echo "  Free space here: $(df -h . | awk 'NR==2{print $4}')"
echo "  Filesystem here: $(diskutil info "$(df . | awk 'NR==2{print $1}')" 2>/dev/null | awk -F: '/Type \(Bundle\)/{gsub(/ /,"",$2);print $2}')"

echo "== Tools =="
xcode-select -p >/dev/null 2>&1 && ok "Xcode Command Line Tools" || miss "Xcode Command Line Tools" "xcode-clt"
command -v brew    >/dev/null && ok "Homebrew"            || miss "Homebrew" "brew"
command -v git     >/dev/null && ok "Git $(git --version | awk '{print $3}')" || miss "Git" "git"
command -v python3 >/dev/null && ok "Python $(python3 --version | awk '{print $2}')" || miss "Python 3" "python"
command -v cmake   >/dev/null && ok "CMake"               || miss "CMake" "cmake"
command -v scons   >/dev/null && ok "SCons"               || miss "SCons (builds the Godot extension)" "scons"
command -v gh      >/dev/null && ok "GitHub CLI"          || miss "GitHub CLI" "gh"
if [[ -d "/Applications/Godot.app" ]] || command -v godot >/dev/null; then ok "Godot"; else miss "Godot 4.7" "godot"; fi
VENV="$(cd "$(dirname "$0")/.." && pwd)/.venv"
"$VENV/bin/python" -c "import jsbsim" 2>/dev/null && ok "JSBSim Python package (.venv)" || miss "JSBSim Python package (.venv)" "jsbsim-py"

echo
if [[ ${#MISSING[@]} -eq 0 ]]; then echo "All set."; exit 0; fi
echo "Missing: ${MISSING[*]}"
[[ $INSTALL -eq 0 ]] && { echo "Run with --install to install them."; exit 1; }

for m in "${MISSING[@]}"; do
  case "$m" in
    xcode-clt) xcode-select --install || true; echo "  -> finish the Xcode popup, then re-run." ;;
    brew)      echo "  -> install Homebrew from https://brew.sh first, then re-run."; exit 1 ;;
    git|cmake|scons|gh) brew install "$m" ;;
    python)    brew install python ;;
    godot)     brew install --cask godot ;;
    jsbsim-py) PY="$(command -v python3.12 || command -v python3)"; "$PY" -m venv "$VENV" && "$VENV/bin/pip" install -q jsbsim ;;
  esac
done
echo "Done. Re-run without --install to verify."
