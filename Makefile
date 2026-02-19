.PHONY: build install setup release clean uninstall

INSTALL_DIR = $(HOME)/.local/bin
BIN = cc-beacon
CONFIG = $(HOME)/.config/ccbeacon.conf

build:
	swift build -c release

install: build
	mkdir -p $(INSTALL_DIR)
	cp $$(swift build -c release --show-bin-path)/$(BIN) $(INSTALL_DIR)/$(BIN)
	chmod +x $(INSTALL_DIR)/$(BIN)
	@echo "✓ Installed to $(INSTALL_DIR)/$(BIN)"
	@mkdir -p $(HOME)/.config
	@if [ ! -f $(CONFIG) ]; then cp ccbeacon.conf $(CONFIG); echo "✓ Config created at $(CONFIG)"; fi

setup: install
	@bash setup-hooks.sh
	@echo ""
	@echo "✓ Restart Claude Code to activate hooks."

# Build universal binary for GitHub releases
release:
	swift build -c release --arch arm64 --arch x86_64
	mkdir -p dist
	cp $$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$(BIN) dist/cc-beacon-macos
	@echo "✓ Universal binary at dist/cc-beacon-macos"

test:
	echo '{"hook_event_name":"Stop","cwd":"$(PWD)","message":"Test notification"}' \
		| $(INSTALL_DIR)/$(BIN) &

clean:
	swift package clean
	rm -rf .build dist

uninstall:
	rm -f $(INSTALL_DIR)/$(BIN)
	rm -f $(CONFIG)
	@echo "✓ Removed. Clean hooks from ~/.claude/settings.json manually."
