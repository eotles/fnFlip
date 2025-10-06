# fnFlip

A tiny macOS menu bar app to switch between media keys and standard function keys.

Toggle MacOS keyboard between Standard F1, F2, etc. and Hardware Keys. Helpful when using Epic Hyperspace on a Mac.

Technical highlights:
- Fast, non-blocking OS toggle
- Default optional Launch at Login (uses SMAppService)
- IconGen called during build phase automatically generates icon assets for application & installer
- Autopackage functionality quickly takes notarized archive and makes .pkg
- Signed, hardened runtime, and ready for notarized packaging

## Install

Download the latest signed package from Releases and run the installer.

## Build

Xcode 15+ on macOS 13+.

## License

MIT + Commons Clause. Internal use is allowed, selling the software or offering it as a paid service is not, unless you obtain a commercial license. See [LICENSE](./LICENSE).

Commercial licensing: hi@eotles.com
