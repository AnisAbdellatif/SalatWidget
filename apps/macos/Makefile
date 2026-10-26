.PHONY: build test perf app run install icon clean mawakit

# With only the Command Line Tools installed (no Xcode), SwiftPM doesn't find
# swift-testing on its own; point it at the copy that ships with them.
CLT_DEV := /Library/Developer/CommandLineTools/Library/Developer
ifeq ($(shell xcode-select -p),/Library/Developer/CommandLineTools)
TEST_FLAGS := -Xswiftc -F -Xswiftc $(CLT_DEV)/Frameworks \
	-Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing \
	-Xlinker -F -Xlinker $(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib
endif

# Work around SDKs the Command Line Tools can't build SwiftUI with (see scripts/toolchain.sh).
FALLBACK_SDK := $(shell scripts/toolchain.sh)
ifneq ($(FALLBACK_SDK),)
export SDKROOT := $(FALLBACK_SDK)
endif

# The Rust core's Swift artifacts (static library + generated API), rebuilt when the
# MawaKit checkout changes. Cargo makes this fast when nothing changed.
MAWAKIT_PATH ?= ../../../MawaKit
export MAWAKIT_PATH

mawakit:
	@$(MAKE) --no-print-directory -C $(MAWAKIT_PATH) swift

build: mawakit
	swift build

# Unit tests, including deterministic performance budgets.
test: mawakit
	swift test $(TEST_FLAGS)

# Runtime check: CPU, wakeups and redraws with the panel closed/open (≈1 min).
perf: mawakit
	scripts/perf-check.sh

app: mawakit
	scripts/build-app.sh

run: app
	open build/SalatWidget.app

install: app
	rm -rf /Applications/SalatWidget.app
	cp -R build/SalatWidget.app /Applications/
	open /Applications/SalatWidget.app

icon:
	swift scripts/make-icon.swift

clean:
	rm -rf .build build
