# CarromDuo

A native SwiftUI and SpriteKit carrom game for iPhone and iPad. The board keeps a square logical coordinate space and scales to the actual available display area, including the iPhone Duo simulator.

## Build

Open `CarromDuo.xcodeproj` in Xcode 27.1 or later, select the CarromDuo scheme and an iOS simulator, then Run. The project targets iOS 17.0 and uses no third-party dependencies.

## Play

- Choose pass-and-play or play against the computer.
- Drag back from the striker and release to shoot. Drag horizontally on the baseline to reposition the striker.
- A potted own coin scores one point and earns another shot. Pocketing the queen requires an own coin on the same or next shot; a queen that is not covered returns to center.
- Pocketing the striker is a foul and deducts one point.

This is an initial playable rules prototype; match-end / full tournament rules and final art/audio are future work.
