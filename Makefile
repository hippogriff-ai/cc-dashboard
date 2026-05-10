.PHONY: project backend-build app-build app-run test test-backend test-app clean

# Make's /bin/sh shell doesn't source ~/.zshrc, so user-installed binaries like
# `bun` (default install: ~/.bun/bin) aren't found via PATH. Prepend the
# canonical install location AND `/opt/homebrew/bin` to be hospitable to both
# install paths. Falls through to the user's existing PATH if neither holds it.
export PATH := $(HOME)/.bun/bin:/opt/homebrew/bin:$(PATH)

# Regenerate Xcode project from project.yml
project:
	cd app && xcodegen generate

# Compile the TypeScript sidecar to a single binary
backend-build:
	cd backend && bun build --compile --minify --target=bun-darwin-arm64 src/server.ts --outfile cc-dashboard-backend

# Build the Swift app (Release)
app-build: project backend-build
	xcodebuild -project app/cc-dashboard.xcodeproj -scheme cc-dashboard -configuration Release -derivedDataPath app/build

# Run the built app
app-run: app-build
	open app/build/Build/Products/Release/cc-dashboard.app

# All tests
test: test-backend test-app

test-backend:
	cd backend && bun test

test-app: project
	xcodebuild -project app/cc-dashboard.xcodeproj -scheme cc-dashboard test -derivedDataPath app/build

clean:
	rm -rf app/build app/cc-dashboard.xcodeproj backend/cc-dashboard-backend backend/dist
	@# Reap stranded sidecars from prior `make test-app` runs that predate the
	@# Loop 35 ppid-watchdog. The `|| true` keeps `make clean` exit-0 when no
	@# zombies are running. New sidecars (with watchdog) self-clean on parent
	@# death so this is a one-time safety net for old binaries on disk.
	@pkill -f 'cc-dashboard.app/Contents/Resources/backend/cc-dashboard-backend' 2>/dev/null || true
