APP_NAME   := CloudDrop
BUNDLE_ID  := com.hurayraiit.clouddrop
APP        := build/$(APP_NAME).app
# How long `make quit` waits for a normal quit before killing the app.
QUIT_WAIT  := 10
# ffmpeg compressing for CloudDrop. The [p] stops the pattern matching the shell that runs pkill.
FFMPEG_PATTERN := ffmpeg.*/clouddro[p]-compressed/

# Swift Testing ships with Command Line Tools but isn't on SwiftPM's search path (ADR 0001).
DEV_DIR        := $(shell xcode-select -p)
TESTING_FW     := $(DEV_DIR)/Library/Developer/Frameworks
TESTING_LIB    := $(DEV_DIR)/Library/Developer/usr/lib
TESTING_PLUGIN := $(DEV_DIR)/usr/lib/swift/host/plugins/testing
TEST_FLAGS     := -Xswiftc -F -Xswiftc $(TESTING_FW) \
                  -Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGIN) \
                  -Xlinker -rpath -Xlinker $(TESTING_FW) \
                  -Xlinker -rpath -Xlinker $(TESTING_LIB)

.PHONY: app test quit install uninstall clean

app:
	swift build -c release --product $(APP_NAME)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp "$$(swift build -c release --show-bin-path)/$(APP_NAME)" $(APP)/Contents/MacOS/
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign - --identifier $(BUNDLE_ID) $(APP)

# Fails if the tests fail or if no tests ran at all: with the wrong flags,
# `swift test` silently runs zero Swift Testing tests and exits 0.
test:
	@out=$$(swift test $(TEST_FLAGS) 2>&1); status=$$?; \
	echo "$$out"; \
	[ $$status -eq 0 ] || exit $$status; \
	echo "$$out" | grep -Eq 'Test run with [1-9][0-9]* tests?' || { echo "make test: no tests ran" >&2; exit 1; }

# SIGTERM makes the app quit normally, so applicationWillTerminate stops ffmpeg and saves waiting Captures.
# It's killed only if it hasn't quit within QUIT_WAIT seconds, and then any ffmpeg it left is stopped too;
# the next launch's sweep saves the Captures. The wait also matters for install: opening the app while the
# old one is still exiting sends a reopen event to the dying process instead of launching (error -600).
quit:
	@pgrep -x $(APP_NAME) >/dev/null || exit 0; \
	pkill -TERM -x $(APP_NAME); \
	for i in $$(seq $$(( $(QUIT_WAIT) * 10 ))); do pgrep -x $(APP_NAME) >/dev/null || break; sleep 0.1; done; \
	if pgrep -x $(APP_NAME) >/dev/null; then \
		echo "$(APP_NAME) didn't quit within $(QUIT_WAIT) s, killing it" >&2; \
		pkill -KILL -x $(APP_NAME); \
		pkill -TERM -f '$(FFMPEG_PATTERN)'; \
		for i in $$(seq 20); do pgrep -x $(APP_NAME) >/dev/null || break; sleep 0.1; done; \
	fi; \
	sleep 0.5

install: app quit
	rm -rf /Applications/$(APP_NAME).app
	cp -R $(APP) /Applications/
	open /Applications/$(APP_NAME).app

uninstall: quit
	rm -rf /Applications/$(APP_NAME).app

clean:
	rm -rf .build build
