#!/bin/sh
# Run the test suite. On a Command Line Tools-only machine the Swift Testing macro plugin
# lives in a subfolder the build doesn't always search, so point the compiler at it.
P=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
if [ -f "$P/libTestingMacros.dylib" ]; then
  exec swift test -Xswiftc -plugin-path -Xswiftc "$P" "$@"
fi
exec swift test "$@"
