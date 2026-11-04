PREFIX ?= /usr/local
SWIFTC ?= swiftc
FLAGS  := -O

.PHONY: all universal install clean test

all: axmd

axmd: axmd.swift
	$(SWIFTC) $(FLAGS) axmd.swift -o axmd

universal: axmd.swift
	$(SWIFTC) $(FLAGS) -target arm64-apple-macos13.0 axmd.swift -o axmd-arm64
	$(SWIFTC) $(FLAGS) -target x86_64-apple-macos13.0 axmd.swift -o axmd-x86_64
	lipo -create -output axmd axmd-arm64 axmd-x86_64
	rm -f axmd-arm64 axmd-x86_64
	strip -S -x axmd

install: axmd
	install -d $(PREFIX)/bin
	install -m 0755 axmd $(PREFIX)/bin/axmd

test: axmd
	./axmd --help 2>&1 | grep -q "usage: axmd"
	cmp -s axmd.swift skills/axmd-computer-use/scripts/axmd.swift
	zsh -n skills/axmd-computer-use/scripts/loop.sh

clean:
	rm -f axmd axmd-arm64 axmd-x86_64
