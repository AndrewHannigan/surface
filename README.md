# surface

Float a draggable file thumbnail on your screen. Double-click to open the file, or drag it into any app. The window closes automatically after a successful drag.

## Install

```
brew install AndrewHannigan/tap/surface
```

## Usage

```
surface <file>
```

## Building

Requires macOS and Xcode (or Xcode Command Line Tools).

Build a universal binary (arm64 + x86_64):

```bash
swiftc -O -o surface_arm64 -target arm64-apple-macosx11.0 -framework Cocoa -framework QuickLookThumbnailing surface.swift
swiftc -O -o surface_x86 -target x86_64-apple-macosx11.0 -framework Cocoa -framework QuickLookThumbnailing surface.swift
lipo -create surface_arm64 surface_x86 -output surface
rm surface_arm64 surface_x86
```

Or build for the current architecture only:

```bash
swiftc -O -o surface -framework Cocoa -framework QuickLookThumbnailing surface.swift
```

## Deploying

1. Commit and tag a new version:

   ```bash
   git add surface.swift
   git commit -m "Description of changes"
   git tag vX.Y.Z
   git push origin main vX.Y.Z
   ```

2. Build the universal binary (see above) and create a GitHub release:

   ```bash
   gh release create vX.Y.Z --title "vX.Y.Z" --notes "Release notes"
   gh release upload vX.Y.Z surface
   ```

3. Get the SHA256 of the uploaded binary:

   ```bash
   curl -sL https://github.com/AndrewHannigan/surface/releases/download/vX.Y.Z/surface | shasum -a 256
   ```

4. Update the formula in [homebrew-tap](https://github.com/AndrewHannigan/homebrew-tap) — set the new version, URL tag, and SHA256 in `Formula/surface.rb`, then commit and push.
