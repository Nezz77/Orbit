# Orbit

Orbit brings a teleprompter, notch panel, trackpad controls, cleanup preview, and download queue into one native macOS app with Liquid Glass.

## Build

Orbit targets macOS 26 and later. Open `Orbit.xcodeproj` in Xcode, select the **Orbit** scheme and **My Mac**, then choose **Product > Run**. To regenerate the project after editing `project.yml`, run `xcodegen generate`.

## Tools

- **Teleprompter** imports plain text and supports timed scrolling, on-device speech following, and voice-activated scrolling. The two voice modes use microphone access, and speech following uses Speech Recognition.
- **Notch** shows system status, media controls, and a timer. Clipboard history is opt-in and stays in memory while Orbit runs.
- **Trackpad** maps edge gestures to brightness and volume. Media key controls use macOS Accessibility access.
- **Cleanup** previews eligible caches and logs and moves selected items to Trash after confirmation.
- **Downloads** queues direct HTTP and HTTPS links, keeps transfer history, and resumes a partial transfer when the server supports it.

Notices for Atoll, Mac Cleaner, Prism, SlideSense, and Textream are included in `Resources/Licenses`.
