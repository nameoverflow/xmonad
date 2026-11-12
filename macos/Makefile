.PHONY: all test clean
all: build/xmonad-macos build/xmonad-layout
build/xmonad-layout: Layout.hs ../src/XMonad/StackSet.hs
	mkdir -p build
	ghc -O -i../src -outputdir build Layout.hs -o $@
build/xmonad-macos: main.swift
	mkdir -p build
	swiftc -O main.swift -framework Cocoa -framework Carbon -framework ApplicationServices -o $@
test: all
	test "$$(build/xmonad-layout 0 0 1000 800 3 1 0.5)" = "$$(printf '0 0 500 800\n500 0 500 400\n500 400 500 400')"
clean:
	rm -rf build
