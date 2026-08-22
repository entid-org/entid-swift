# Everything CI runs, runnable locally with the same commands.
SWIFT ?= swift
SPEC ?= spec
GENERATED := Sources/BusinessID/Generated

.DEFAULT_GOAL := check

.PHONY: check
check: verify-lock format-check lint build test conformance generated-check ## Everything a pull request must pass

.PHONY: build
build: ## Build debug and release with warnings as errors
	$(SWIFT) build
	$(SWIFT) build -c release

.PHONY: test
test: ## Run every test
	$(SWIFT) test

.PHONY: conformance
conformance: ## Run the shared corpus through the testee
	$(SWIFT) build --product businessid-testee
	$(SWIFT) run businessid-conformance-runner --cases $(SPEC)/businessid-conformance.binpb

.PHONY: generate
generate: ## Compile the rule bundle to Swift
	$(SWIFT) run businessid-gen --rules $(SPEC)/businessid-rules.binpb --lock rules.lock --out $(GENERATED)

.PHONY: generated-check
generated-check: ## Fail when the committed generated code is stale
	$(SWIFT) run businessid-gen --rules $(SPEC)/businessid-rules.binpb --lock rules.lock --out $(GENERATED) --check

.PHONY: proto
proto: ## Regenerate the Protobuf code the generator reads (needs protoc and protoc-gen-swift)
	protoc -I proto \
		--swift_out=Sources/BusinessIDWire/Generated \
		--swift_opt=Visibility=Package \
		--swift_opt=FileNaming=PathToUnderscores \
		proto/libbusinessid/ir/v1/rules.proto \
		proto/libbusinessid/conformance/v1/conformance.proto \
		proto/libbusinessid/testee/v1/testee.proto

.PHONY: format
format: ## Apply the formatter
	$(SWIFT) format format -r -i -p Sources Tests Package.swift

.PHONY: format-check
format-check: ## Fail on a formatting difference
	$(SWIFT) format lint -r -s -p Sources Tests Package.swift

.PHONY: lint
lint: ## Run SwiftLint strictly
	swiftlint lint --strict --quiet

.PHONY: coverage
coverage: ## Measure line coverage against its gates
	./Tools/coverage.sh

.PHONY: fuzz
fuzz: ## A short deterministic fuzz run
	$(SWIFT) run -c release businessid-fuzz --rounds 20000

.PHONY: bench
bench: ## Regression benchmarks
	$(SWIFT) run -c release businessid-bench

.PHONY: verify-lock
verify-lock: ## Check every digest rules.lock attests
	@./Tools/verify-lock.sh

.PHONY: docs
docs: ## Build the DocC archive
	xcodebuild docbuild -scheme BusinessID -destination 'generic/platform=macOS' \
		-derivedDataPath .build/docc -quiet
	@echo "archive: $$(find .build/docc -name '*.doccarchive' | head -1)"

.PHONY: help
help: ## List the targets
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
