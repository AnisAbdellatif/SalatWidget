.PHONY: test perf app run install hooks

# Entry points for the whole monorepo. Each app also has its own Makefile.
MACOS := apps/macos

test:
	$(MAKE) -C $(MACOS) test

perf:
	$(MAKE) -C $(MACOS) perf

app run install:
	$(MAKE) -C $(MACOS) $@

# Run tests before commits and the runtime perf check before pushes.
hooks:
	git config core.hooksPath .githooks
	@echo "Git hooks enabled (.githooks)."
