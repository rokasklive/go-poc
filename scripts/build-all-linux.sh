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
# 5. macOS amd64 + arm64 — Docker (Zig + macOS SDK) cross-compile
#    Requires the 'wails-cross' image. We build it on demand if missing.
#
#    IMPORTANT: OUTPUT must NOT equal the Docker build's intrinsic output name
#    (bin/<app>-darwin-<arch>), otherwise the task's `mv <src> <OUTPUT>` step
#    fails with "are the same file". We therefore use a '-macos-' suffix.
# ----------------------------------------------------------------------------
MACOS_OK=1
if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "Docker is not available/running — skipping macOS cross-builds."
  echo "macOS cross-compilation from Linux requires Docker (Zig + macOS SDK)."
  MACOS_OK=0
elif ! docker image inspect wails-cross >/dev/null 2>&1; then
  hr
  echo "# 'wails-cross' image not found — building it (one-time, ~minutes / ~1GB)"
  echo "# Equivalent manual command: wails3 task setup:docker"
  if ! wails3 task setup:docker; then
    echo "Failed to build 'wails-cross' image — skipping macOS cross-builds."
    MACOS_OK=0
  fi
fi

if [[ "${MACOS_OK}" -eq 1 ]]; then
  build_target "darwin/amd64" "${BIN_DIR}/${APP_NAME}-macos-amd64" \
    wails3 task darwin:build "ARCH=amd64" "OUTPUT=${BIN_DIR}/${APP_NAME}-macos-amd64"
  build_target "darwin/arm64" "${BIN_DIR}/${APP_NAME}-macos-arm64" \
    wails3 task darwin:build "ARCH=arm64" "OUTPUT=${BIN_DIR}/${APP_NAME}-macos-arm64"
else
  skip_target "darwin/amd64" "Docker unavailable or wails-cross image missing"
  skip_target "darwin/arm64" "Docker unavailable or wails-cross image missing"
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
copy_if_exists "${BIN_DIR}/${APP_NAME}-macos-amd64"  "${APP_NAME}-macos-amd64"
copy_if_exists "${BIN_DIR}/${APP_NAME}-macos-arm64"  "${APP_NAME}-macos-arm64"

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
