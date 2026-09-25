# AI Photo Studio

SwiftUI iOS 16+ foundation for a non-destructive photo editor.

## Open and run

1. On macOS with Xcode 15 or newer, open `photos/AIPhotoStudio.xcodeproj`.
2. Select the `AIPhotoStudio` scheme and an iOS 16+ simulator/device.
3. Build and run. The generated sample image works without bundled assets.
4. Run the `AIPhotoStudioTests` test target for domain, persistence, format, and canvas-state coverage.

The iOS 16 persistence path is Codable JSON. A separately availability-gated
SwiftData backend is included for iOS 17+, because SwiftData itself is not
available on iOS 16.
