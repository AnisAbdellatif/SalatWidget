.PHONY: test test-macos test-desktop perf app run install hooks

# Entry points for the whole monorepo. Each app also has its own Makefile.
MACOS := apps/macos

test: test-macos test-desktop

test-macos:
	$(MAKE) -C $(MACOS) test

# The desktop app's platform-independent parts (countdown text, icon, display model,
# settings). Its Linux-only GTK code is built and tested on Linux (see apps/desktop).
test-desktop:
	cd apps/desktop && cargo fmt --check && cargo test --quiet

perf:
	$(MAKE) -C $(MACOS) perf

app run install:
	$(MAKE) -C $(MACOS) $@

# Run tests before commits and the runtime perf check before pushes.
hooks:
	git config core.hooksPath .githooks
	@echo "Git hooks enabled (.githooks)."
