# Everything CI runs, runnable locally with the same commands.
SWIFT ?= swift
SPEC ?= spec
GENERATED := Sources/EntID/Generated

.DEFAULT_GOAL := verify

# The single entry point of `engine.md` section 12.5: silent when everything
# passes, the failing step's output and only that when one does not. CI calls it
# too, so "green" never has two definitions.
.PHONY: verify
verify: ## Everything, in one command, quiet unless something fails
	@./Tools/verify.sh

.PHONY: check
check: verify ## Alias kept for muscle memory

.PHONY: build
build: ## Build debug and release with warnings as errors
	$(SWIFT) build
	$(SWIFT) build -c release

.PHONY: test
test: ## Run every test
	$(SWIFT) test

# The runner comes from the specification repository and nowhere else, pinned
# to the commit rules.lock records — the same commit as the corpus, so a corpus
# can never be judged by another release's comparator. An engine that wrote its
# own comparator could declare itself conformant by comparing too weakly.
SOURCE_COMMIT := $(shell sed -n 's/^source_commit = "\(.*\)"/\1/p' rules.lock)
# The module path is a property of the pinned commit, not of the organisation
# today: `go run` refuses a path the fetched `go.mod` does not declare. It
# follows the release, so it moves with `source_commit` and not with a rename.
RUNNER := github.com/libbusinessid/spec/cmd/conformance-runner@$(SOURCE_COMMIT)

.PHONY: conformance
conformance: ## Run the shared corpus through the testee, judged by the spec runner
	$(SWIFT) build --product entid-testee
	go run $(RUNNER) -corpus $(SPEC)/entid-conformance.binpb -- \
		$$($(SWIFT) build --product entid-testee --show-bin-path)/entid-testee

.PHONY: generate
generate: ## Compile the rule bundle to Swift
	$(SWIFT) run entid-gen --rules $(SPEC)/entid-rules.binpb --lock rules.lock --out $(GENERATED)

.PHONY: generated-check
generated-check: ## Fail when the committed generated code is stale
	$(SWIFT) run entid-gen --rules $(SPEC)/entid-rules.binpb --lock rules.lock --out $(GENERATED) --check

.PHONY: proto
proto: ## Regenerate the Protobuf code the generator reads (needs protoc and protoc-gen-swift)
	protoc -I proto \
		--swift_out=Sources/EntIDWire/Generated \
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

.PHONY: ios
ios: ## Run the suite on an iOS simulator, as CI does
	@DESTINATION=$$(xcrun simctl list devices available --json \
		| python3 -c "import json,sys; d=json.load(sys.stdin)['devices']; \
			print(next(x['udid'] for k,v in d.items() if 'iOS' in k for x in v))"); \
	xcodebuild test -scheme EntID-Package -destination "id=$$DESTINATION" \
		-only-testing:EntIDTests -quiet

.PHONY: mutation
mutation: ## Apply each targeted mutant and require a test to fail
	./Tools/mutation.sh

.PHONY: coverage
coverage: ## Measure line coverage against its gates
	./Tools/coverage.sh

.PHONY: fuzz
fuzz: ## A short deterministic fuzz run
	$(SWIFT) run -c release entid-fuzz --rounds 20000

.PHONY: bench
bench: ## Regression benchmarks
	$(SWIFT) run -c release entid-bench

.PHONY: verify-lock
verify-lock: ## Check every digest rules.lock attests
	@./Tools/verify-lock.sh

.PHONY: docs
docs: ## Build the DocC archive
	xcodebuild docbuild -scheme EntID -destination 'generic/platform=macOS' \
		-derivedDataPath .build/docc -quiet
	@echo "archive: $$(find .build/docc -name '*.doccarchive' | head -1)"

.PHONY: help
help: ## List the targets
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
