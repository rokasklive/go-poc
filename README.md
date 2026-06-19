# Skill Manager POC

A **build / distribution feasibility** proof-of-concept for a future "Skill Manager"
desktop application. The app you see is intentionally fake — it exists only to
answer one question:

> **Can Wails v3 compile and package a Go + React desktop app for Windows, macOS,
> and Linux from a single Linux build environment?**

## What this POC *is* proving

- A lightweight cross-platform desktop app can be built with **Go + Wails v3 + React + Vite + TypeScript + Radix UI**.
- The **React frontend can call Go backend methods** through Wails' generated bindings.
- A **single Linux builder** can produce artifacts for **Linux, Windows, and macOS** (amd64 + arm64).
- **Node/NPM is only required at build time** — the shipped binary embeds the built frontend and needs no Node at runtime.

## What this POC is *not* proving / not doing

This is **not** a product-functionality POC. There is deliberately **no**:

- real skill installation, update, or deletion;
- skill publishing, Git integration, or Nexus integration;
- authentication, PAT handling, or secrets;
- auto-update, telemetry, assistant detection, routing, state libraries, or a database.

Every backend method returns **dummy data** or a dummy message such as
`"POC only — no real skill operation performed."`

## Stack

| Layer            | Choice                                            |
| ---------------- | ------------------------------------------------- |
| Backend          | Go (`app.go`, `main.go`)                          |
| Desktop shell    | Wails v3 (`v3.0.0-alpha2.104`)                    |
| Frontend         | React + Vite + TypeScript (`react-ts` template)   |
| UI primitives    | Radix UI — `@radix-ui/themes`                     |
| Build orchestration | Taskfiles driven by `wails3 task`              |
| macOS cross-build  | Docker image `wails-cross` (Zig + macOS SDK)    |

## Repository layout

```
.
├── main.go                  # Wails app entry point; binds SkillManagerService
├── app.go                   # SkillManagerService — all dummy backend methods
├── go.mod / go.sum
├── Taskfile.yml             # Wails v3 build orchestration (per-platform includes)
├── build/                   # Generated platform build assets (incl. docker/Dockerfile.cross)
├── frontend/
│   ├── package.json / package-lock.json
│   ├── vite.config.ts
│   ├── index.html
│   ├── src/{main.tsx, App.tsx, styles.css}
│   └── bindings/            # Auto-generated Go→TS bindings (do not edit)
├── scripts/
│   └── build-all-linux.sh   # Attempts all 4 target builds from Linux
└── .github/workflows/
    └── release.yml          # Tag-triggered CI: builds all 4 targets, publishes a Release
```

> The Go module path is `github.com/rokasklive/go-poc`. `frontend/dist` (the built
> frontend) is committed so the `go run` path below works from the module proxy.

## Prerequisites

- **Go** ≥ 1.25 (built with 1.26 here)
- **Node** + **NPM** (build time only)
- **Wails v3 CLI**:
  ```bash
  go install github.com/wailsapp/wails/v3/cmd/wails3@latest
  # ensure it is on PATH:
  export PATH="$(go env GOPATH)/bin:$PATH"
  ```
- Linux GUI dev libraries for native Linux builds: GTK3 + WebKit2GTK (`webkit2gtk-4.1`).
  Run `wails3 doctor` to see exactly what your distro needs.
- **Docker** — only required to cross-compile the **macOS** targets from Linux.

## Run locally (development)

```bash
export PATH="$(go env GOPATH)/bin:$PATH"
wails3 task dev          # hot-reload dev server + native window
```

This opens the desktop window and serves the React frontend with hot reload. Clicking
the role presets / Install / Update / Delete buttons calls the Go backend and shows
the dummy result in the "Last backend result" panel — that is the React→Go proof.

## Run via `go run` (no clone)

You can run the app straight from a published tag — but note this is a **developer**
convenience, not an end-user install path, because it compiles a CGO GUI app from source:

```bash
go run -tags production github.com/rokasklive/go-poc@v0.0.1
```

Important caveats:

- **`-tags production` is required.** Without it the app starts in *dev mode* and exits
  with `unable to connect to frontend server` (it waits for a Vite dev server). A bare
  `go run …@tag` will compile and then crash at startup.
- Your machine needs the **full native build toolchain**: Go + a C compiler (CGO) + the
  platform GUI dev libraries (Linux: GTK3 + WebKit2GTK; macOS: Xcode Command Line Tools).
- It builds for **your current OS only**. For other platforms, use the prebuilt release
  binaries (see *Releasing* below) — that is the clean distribution route for end users.

## Build locally (host platform only)

```bash
export PATH="$(go env GOPATH)/bin:$PATH"
wails3 task build        # builds for the current OS into ./bin
```

## Build all target platforms from Linux

```bash
./scripts/build-all-linux.sh
```

The script prints toolchain versions, runs `wails3 doctor`, installs frontend deps
with `npm ci`, then attempts each target and verifies the artifact exists. Results
land in `./dist`:

```
dist/skill-manager-poc-linux-amd64
dist/skill-manager-poc-windows-amd64.exe
dist/skill-manager-poc-macos-amd64
dist/skill-manager-poc-macos-arm64
```

The first macOS run builds the `wails-cross` Docker image on demand (one-time, ~1 GB).
You can pre-build it with `wails3 task setup:docker`.

## Target platform matrix

| Target          | Method (from Linux)                         | Docker needed | Verified here |
| --------------- | ------------------------------------------- | ------------- | ------------- |
| Linux  amd64    | Native CGO build (GTK3 + WebKit2GTK)        | No            | ✅ SUCCESS    |
| Windows amd64   | Native Go cross-compile (CGO disabled)      | No            | ✅ SUCCESS    |
| macOS  amd64    | Docker `wails-cross` (Zig + macOS SDK)      | Yes           | ✅ SUCCESS    |
| macOS  arm64    | Docker `wails-cross` (Zig + macOS SDK)      | Yes           | ✅ SUCCESS    |

Detailed build findings and a distribution-approach comparison are maintained in `docs/`,
which is kept local and **not committed** to this repo.

## Releasing (CI)

Releases are produced by [`.github/workflows/release.yml`](.github/workflows/release.yml),
which is **triggered by pushing a version tag**. On a tag matching `v*` it spins up a single
`ubuntu-latest` runner, installs Go + Node + the pinned Wails CLI + GTK/WebKit dev libs,
runs `scripts/build-all-linux.sh` (which also builds the `wails-cross` Docker image for the
macOS targets), and publishes all four binaries to a GitHub Release for that tag.

```bash
# 1. Rebuild and commit the embedded frontend if it changed
( cd frontend && npm run build ) && git add frontend/dist && git commit -m "Build frontend"

# 2. Tag and push — the release workflow does the rest
git tag v0.0.1
git push origin v0.0.1
```

The Release will contain:

```
skill-manager-poc-linux-amd64
skill-manager-poc-windows-amd64.exe
skill-manager-poc-macos-amd64
skill-manager-poc-macos-arm64
```

## Known limitations

- **Wails v3 is alpha** (`v3.0.0-alpha2.104`). The API is claimed to be production-stable,
  but commands/structure can still change between releases. Pin the CLI version in CI.
- **macOS cross-builds require Docker** (Zig + macOS SDK). There is no pure-Go path for
  the macOS CGO/WebKit layer.
- **Windows arm64** and **Linux arm64** are supported by the same machinery but were not
  in scope and are not part of the verified matrix above.
- The Linux native build emits GTK4 X11 **deprecation warnings**; these are warnings, not
  errors, and do not affect the produced binary.

## Signing / notarization note

- macOS artifacts produced **from Linux are unsigned** (the build prints
  "Skipping codesign … Sign the .app on macOS before distribution").
- Code signing and notarization are a **separate, platform-native concern** (macOS needs a
  Developer ID + notarization; Windows needs Authenticode) and are **out of scope** for this
  feasibility POC.

## End-user dependency note

- **Node / NPM** are needed only for **development and building** (Vite bundles the frontend).
- The built binary **embeds** `frontend/dist` via Go's `embed`, so **end users do not need
  Node/NPM** — they run a single native executable.
