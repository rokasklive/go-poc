#!/usr/bin/env bash
#
# build-all-linux.sh — attempt all target-platform builds from a single Linux builder.
#
# This is the build/distribution feasibility check for the Skill Manager POC.
# It tries to produce desktop binaries for:
#
#   * Linux   amd64  (native CGO build — needs GTK3 + WebKit2GTK dev libs)
#   * Windows amd64  (native Go cross-compile, CGO disabled — no Docker needed)
#   * macOS   amd64  (Docker + Zig + macOS SDK via the `wails-cross` image)
#   * macOS   arm64  (Docker + Zig + macOS SDK via the `wails-cross` image)
#
# It does NOT fake success: every target is verified by checking that the
# expected artifact file actually exists, and a pass/fail/skip summary is
# printed at the end. A non-zero exit code means at least one target failed.
#
# Usage:
#   ./scripts/build-all-linux.sh
#
set -euo pipefail

# Resolve repo root (this script lives in <root>/scripts) and run from there so
# all the relative paths in the Wails Taskfiles resolve correctly.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

# Ensure the Go bin dir (where `go install` puts wails3) is on PATH.
export PATH="$(go env GOPATH)/bin:${PATH}"

APP_NAME="skill-manager-poc"
BIN_DIR="bin"
DIST_DIR="dist"

# Accumulated per-target results, formatted as "label|STATUS|artifact".
RESULTS=()
OVERALL_EXIT=0

hr() { printf '%s\n' "------------------------------------------------------------"; }

# require <command> — fail fast with a clear message if a tool is missing.
require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required tool '$1' not found on PATH." >&2
    exit 1
  fi
}

# build_target <label> <expected-artifact> <command...>
# Runs the build command and records SUCCESS only if it exits 0 AND the
# expected artifact exists on disk afterwards.
build_target() {
  local label="$1"; local artifact="$2"; shift 2
  hr
  echo ">>> Building: ${label}"
  echo ">>> Command : $*"
  if "$@" && [[ -e "${artifact}" ]]; then
    echo ">>> OK: ${artifact}"
    RESULTS+=("${label}|SUCCESS|${artifact}")
  else
    echo ">>> FAILED: ${label} (see output above)"
    RESULTS+=("${label}|FAILED|${artifact}")
    OVERALL_EXIT=1
  fi
}

# skip_target <label> <reason> — record a target as skipped (not faked).
skip_target() {
  RESULTS+=("$1|SKIPPED|$2")
}

# ----------------------------------------------------------------------------
# 1. Toolchain diagnostics
# ----------------------------------------------------------------------------
require go
require node
require npm
require wails3

hr
echo "# Toolchain versions"
echo "Go     : $(go version)"
echo "Node   : $(node --version)"
echo "NPM    : $(npm --version)"
echo "Wails3 : $(wails3 version)"
if command -v docker >/dev/null 2>&1; then
  echo "Docker : $(docker --version)"
else
  echo "Docker : not installed (macOS cross-builds will be skipped)"
fi

hr
echo "# wails3 doctor"
# Doctor is diagnostic only; never let it abort the build run.
wails3 doctor || echo "(wails3 doctor returned non-zero — continuing)"

# ----------------------------------------------------------------------------
# 2. Frontend dependencies (reproducible install)
# ----------------------------------------------------------------------------
hr
echo "# Installing frontend dependencies with 'npm ci'"
if [[ -f frontend/package-lock.json ]]; then
  ( cd frontend && npm ci )
else
  echo "WARNING: frontend/package-lock.json not found; falling back to 'npm install'."
  ( cd frontend && npm install )
fi

mkdir -p "${DIST_DIR}"

# ----------------------------------------------------------------------------
# 3. Linux amd64 — native CGO build
# ----------------------------------------------------------------------------
build_target "linux/amd64" "${BIN_DIR}/${APP_NAME}-linux-amd64" \
  wails3 task linux:build "OUTPUT=${BIN_DIR}/${APP_NAME}-linux-amd64"

# ----------------------------------------------------------------------------
# 4. Windows amd64 — native Go cross-compile (CGO disabled, no Docker)
#    NOTE: the windows:build task always writes bin/<app>.exe and ignores OUTPUT.
# ----------------------------------------------------------------------------
build_target "windows/amd64" "${BIN_DIR}/${APP_NAME}.exe" \
  wails3 task windows:build

# ----------------------------------------------------------------------------
# 5. macOS universal .app — Docker (Zig + macOS SDK) cross-compile + bundle
#    Builds amd64 + arm64, lipo-joins them into one universal binary, wraps it
#    in a double-clickable `.app` bundle, and zips it. The bundle + zip are pure
#    file operations, so this all runs on Linux. We ship a zip because a `.app`
#    is a directory; zipping (with -y) also preserves the executable bit so
#    Finder treats it as a launchable app rather than opening it as a document.
#    Only code SIGNING needs extra tooling/secrets (see README/notes), not this.
#    Requires the 'wails-cross' image; we build it on demand if missing.
# ----------------------------------------------------------------------------
MACOS_APP_DIR="${BIN_DIR}/${APP_NAME}.app"
MACOS_APP_ZIP="${BIN_DIR}/${APP_NAME}-macos-universal.app.zip"

MACOS_OK=1
if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "Docker is not available/running — skipping macOS packaging."
  echo "macOS cross-compilation from Linux requires Docker (Zig + macOS SDK)."
  MACOS_OK=0
elif ! docker image inspect wails-cross >/dev/null 2>&1; then
  hr
  echo "# 'wails-cross' image not found — building it (one-time, ~minutes / ~1GB)"
  echo "# Equivalent manual command: wails3 task setup:docker"
  if ! wails3 task setup:docker; then
    echo "Failed to build 'wails-cross' image — skipping macOS packaging."
    MACOS_OK=0
  fi
fi
if [[ "${MACOS_OK}" -eq 1 ]] && ! command -v zip >/dev/null 2>&1; then
  echo "'zip' not found — required to package the macOS .app; skipping macOS."
  MACOS_OK=0
fi

if [[ "${MACOS_OK}" -eq 1 ]]; then
  hr
  echo ">>> Building & packaging: darwin/universal (.app)"
  rm -rf "${MACOS_APP_DIR}" "${MACOS_APP_ZIP}"
  if wails3 task darwin:package:universal && [[ -d "${MACOS_APP_DIR}" ]]; then
    # Zip from inside bin/ so the archive root is "<app>.app" (not "bin/...").
    ( cd "${BIN_DIR}" && zip -ry -q "$(basename "${MACOS_APP_ZIP}")" "${APP_NAME}.app" )
    if [[ -e "${MACOS_APP_ZIP}" ]]; then
      echo ">>> OK: ${MACOS_APP_ZIP}"
      RESULTS+=("darwin/universal|SUCCESS|${MACOS_APP_ZIP}")
    else
      echo ">>> FAILED: darwin/universal (zip step produced no archive)"
      RESULTS+=("darwin/universal|FAILED|zip produced no archive")
      OVERALL_EXIT=1
    fi
  else
    echo ">>> FAILED: darwin/universal (.app not produced)"
    RESULTS+=("darwin/universal|FAILED|${MACOS_APP_DIR}")
    OVERALL_EXIT=1
  fi
else
  skip_target "darwin/universal" "Docker/zip unavailable or wails-cross image missing"
fi

# ----------------------------------------------------------------------------
# 6. Collect successful artifacts into dist/
# ----------------------------------------------------------------------------
hr
echo "# Collecting artifacts into ${DIST_DIR}/"
copy_if_exists() {
  local src="$1"; local dst="$2"
  if [[ -e "${src}" ]]; then
    cp -f "${src}" "${DIST_DIR}/${dst}"
    echo "  ${DIST_DIR}/${dst}"
  fi
}
copy_if_exists "${BIN_DIR}/${APP_NAME}-linux-amd64"  "${APP_NAME}-linux-amd64"
copy_if_exists "${BIN_DIR}/${APP_NAME}.exe"          "${APP_NAME}-windows-amd64.exe"
copy_if_exists "${MACOS_APP_ZIP}"                    "$(basename "${MACOS_APP_ZIP}")"

# ----------------------------------------------------------------------------
# 7. Summary
# ----------------------------------------------------------------------------
hr
echo "# Build summary"
printf '%-16s %-9s %s\n' "TARGET" "STATUS" "ARTIFACT / NOTE"
for entry in "${RESULTS[@]}"; do
  IFS='|' read -r label status detail <<< "${entry}"
  printf '%-16s %-9s %s\n' "${label}" "${status}" "${detail}"
done
hr

if [[ "${OVERALL_EXIT}" -eq 0 ]]; then
  echo "RESULT: all attempted targets succeeded."
else
  echo "RESULT: one or more targets FAILED — see output and summary above."
fi
echo "NOTE: macOS binaries built on Linux are UNSIGNED. Signing/notarization is a"
echo "      separate, macOS-only concern and is out of scope for this POC."

exit "${OVERALL_EXIT}"
