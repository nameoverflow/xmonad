# macOS experiment

This is an early port experiment in the xmonad fork, not a replacement for xmonad. It uses the upstream `XMonad.StackSet` module and shares the core Tall geometry extracted into a platform-independent module, with a Swift Accessibility backend. It does **not** load `xmonad.hs` or `xmonad-contrib`; real layout and action compatibility remains future work. The Swift process currently maintains the window order, and invokes a short-lived Haskell helper for each layout. No native desktop interaction has been validated yet.

Build on macOS with GHC and Xcode command-line tools: `make -C macos test`. Run `macos/build/xmonad-macos` after granting Accessibility access to the executable. The manager moves visible windows; save work and quit other window managers before testing. It exits when permission is absent. macOS continues to manage Spaces; full-screen windows and nonstandard windows may not work.

Shortcuts use Control-Option: J/K focus; Shift-J/K swap; Return moves a window to master; H/L change master ratio; comma/period adjust master count; Space retile; P pause. Ctrl-C quits. Window discovery currently polls once per second. Multiple screens have separate stacks in Swift, but share the layout parameters. This prototype is not suitable for daily use.
