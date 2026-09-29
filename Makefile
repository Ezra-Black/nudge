# Common tasks. Run `make help` to list them.
.DEFAULT_GOAL := help
SWIFT_SOURCES := Sources Tests Package.swift

.PHONY: help build run test test-swift test-engine lint format clean site site-serve

help: ## List the available tasks
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  make %-12s %s\n", $$1, $$2}'

build: ## Build Nudge.app (settings in .env, see .env.example)
	./scripts/build.sh

run: build ## Build, then open Nudge
	@set -a; [ -f .env ] && . ./.env; set +a; open "$${NUDGE_APP_PATH:-build/Nudge.app}"

test: test-swift test-engine ## Run every test

test-swift: ## Run the Swift tests
	swift test

test-engine: ## Run the Rust engine tests
	cargo test --manifest-path engine/Cargo.toml --locked

lint: ## Check formatting and lints without changing files
	swift format lint --strict --recursive --configuration .swift-format $(SWIFT_SOURCES)
	cargo fmt --manifest-path engine/Cargo.toml -- --check
	cargo clippy --manifest-path engine/Cargo.toml --all-targets --locked -- -D warnings

format: ## Format all Swift and Rust code
	swift format format --in-place --recursive --configuration .swift-format $(SWIFT_SOURCES)
	cargo fmt --manifest-path engine/Cargo.toml

clean: ## Remove build output
	rm -rf .build build engine/target

site: ## Assemble the website into build/site
	rm -rf build/site && mkdir -p build/site
	cp -R site/. build/site/
	cp -R docs/images build/site/images

site-serve: site ## Preview the website at http://127.0.0.1:8000
	python3 -m http.server 8000 --bind 127.0.0.1 --directory build/site
