# Mac Guitar Recording App – Architecture

**Last updated:** 2026-08-07 (UI element inventory + status states clarified)  
**Goal:** Record front-camera video + synchronized mixed audio of guitar (processed through Neural DSP) playing over background music (Spotify, YouTube, etc.) on a MacBook.

## Decision Summary

- **Option chosen:** Standalone native Mac application (Swift + SwiftUI)
- **Browser option discarded:** Not viable because browsers cannot host Neural DSP / AU / VST plugins
- **Audio capture:** Core Audio Process Taps only (ScreenCaptureKit removed)
- **Minimum OS:** macOS 14.2 (Sonoma) or later
- **VST handling:** External (user runs Neural DSP standalone or in a DAW). The app captures the resulting system audio mix. AU hosting inside the app is deferred.

## High-Level Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                     Native Mac App (Swift + SwiftUI)         │
├──────────────────────────────────────────────────────────────┤
│  UI Layer                                                    │
│  • Live camera preview                                       │
│  • System audio level meters                                 │
│  • Record / Stop / Pause                                     │
│  • Settings (resolution, frame rate, sample rate,            │
│    orientation (vertical / horizontal),                      │
│    global vs selected processes)                             │
│  • Output file management                                    │
├──────────────────────────────────────────────────────────────┤
│  Capture Engine                                              │
│  ├── VideoCapture                                            │
│  │     AVCaptureSession → Front camera CMSampleBuffers       │
│  │                                                           │
│  └── AudioCapture                                            │
│        Core Audio Process Taps (CATapDescription)            │
│        → Aggregate device → clean PCM buffers                │
│        (global system audio or selected processes)           │
├──────────────────────────────────────────────────────────────┤
│  Sync & Mux Layer                                            │
│  • Shared timing / master clock                              │
│  • AVAssetWriter                                             │
│  • Align presentation timestamps from camera + audio         │
│  • Format conversion if needed                               │
├──────────────────────────────────────────────────────────────┤
│  Output                                                      │
│  • Single .mov / .mp4 (H.264/HEVC + AAC)                     │
│  • Optional future multi-track support                       │
└──────────────────────────────────────────────────────────────┘
```

## Component Responsibilities

### UI Layer
- SwiftUI-based interface (all elements map to standard SwiftUI / native Xcode controls)
- Real-time camera preview
- Audio level meters driven by the Process Tap stream
- Simple recording controls and basic settings (resolution, frame rate, sample rate, orientation vertical/horizontal, audio source)
- File management for recorded takes

**Concrete UI elements (from mockups) – all easily available in Xcode:**

**Main window**
- Dark window + rounded panel → standard `Window` + `ZStack` / `.background`
- Large camera preview area → `AVCaptureVideoPreviewLayer` wrapped in `NSViewRepresentable`
- Gear icon (top-right) → SF Symbol `"gearshape"`
- Stereo level meters → `HStack` of `Rectangle`s or custom `Canvas` / progress-style view
- Status text (Idle → Recording… → Paused) → plain `Text`
- Big red circular Record button → `Button` + `Circle()` (inner square via SF Symbol or shape)
- Stop button (white square) and Pause button (two vertical bars) → same pattern, different shapes

**Settings sheet**
- Floating sheet → native `.sheet` or `.popover`
- Segmented controls (Resolution, Frame Rate, Sample Rate, Orientation, Audio Source) → `Picker` with `.pickerStyle(.segmented)`
- Labels → plain `Text`
- “Choose…” button → standard `Button`
- Save path field → `TextField` or `Text` with dark background
- Small chevron / refresh icons → SF Symbols (`"arrow.clockwise"`, etc.)

### VideoCapture
- Uses AVFoundation / AVCaptureSession
- Targets the built-in front camera (FaceTime camera)
- Produces timed CMSampleBuffers

### AudioCapture
- Uses Core Audio Process Taps (introduced in macOS 14.2)
- Creates a CATapDescription (global stereo tap or process-scoped)
- Builds an aggregate device that includes the tap
- Delivers clean PCM audio buffers
- Supports:
  - Global system audio (everything playing to the speakers)
  - Selective capture of specific processes (e.g. Neural DSP + Spotify only)
- Captures independently of system volume in typical configurations
- No screen content or ScreenCaptureKit involvement

### Sync & Mux Layer
- Receives timed sample buffers from both camera and audio sources
- Uses a common timing reference / master clock
- Feeds AVAssetWriter (or multiple AVAssetWriterInputs)
- Aligns presentation timestamps for frame-accurate A/V sync
- Handles any necessary sample-rate or format conversion

### Output
- Single container file (.mov or .mp4)
- Video: H.264 or HEVC
- Audio: AAC
- Designed so multi-track export can be added later without changing the capture path

## Recommended Usage Model

1. User launches Neural DSP in standalone mode (or inside a DAW).
2. Guitar signal is routed into the audio interface → Neural DSP.
3. Background music plays normally in Spotify, YouTube, Apple Music, etc.
4. Both Neural DSP output and the music are sent to the same output device (speakers or headphones).
5. The app captures:
   - Front camera video
   - The mixed system audio via the Process Tap
6. AVAssetWriter produces one synchronized movie file.

## Permissions Required
- Camera
- System Audio Recording (Process Taps)

## Explicitly Out of Scope for v1
- Hosting Neural DSP (or any AU/VST) inside the app
- ScreenCaptureKit or any screen-content capture
- Virtual audio drivers (BlackHole, Loopback, etc.)
- Multi-track recording / separate stems
- Real-time monitoring / low-latency monitoring path inside the app
- Complex editing or post-processing features

## Future Extension Points
- Per-process isolation → separate music and guitar tracks
- Optional in-app AU hosting of Neural DSP
- Multi-track export
- Hardware input selection and latency compensation
- Simple trim / levels tools after recording

## Rationale Notes
- Core Audio Process Taps provide a clean, audio-only, modern API without the overhead or permission model of screen capture.
- Keeping Neural DSP external dramatically reduces complexity while still delivering the required mixed result.
- AVAssetWriter + timed sample buffers is the standard native way to achieve reliable A/V sync on macOS.
