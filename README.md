# AV Recorder

A macOS app that records your **front camera** together with the **system audio mix** into a single synchronized `.mov` file. It's built for capturing things like playing guitar live — your webcam video plus the sound that's actually coming out of your speakers (e.g. guitar through Neural DSP plus background playback).

## What it does

- **Live preview** of your front (FaceTime) camera while you set up.
- **Live level meter** showing the current system audio so you can confirm sound is flowing before you hit record.
- **One-click recording** — captures camera video + the full system audio mix and muxes them into a single video file.
- **Audio/video sync** — everything is placed on a single shared timeline, so lip-sync / guitar-sync stays tight.
- **Settings** — choose horizontal (16:9) or vertical (9:16) output, pick a save folder, and nudge an "audio diff" offset (in milliseconds) if you need to manually tune sync.

## Requirements

- **macOS 14.4 or later** (required for the Core Audio process-tap API used to capture system audio).
- Camera + System Audio recording permission grants on first launch.

---

## Architecture (for agents / contributors)

### Project layout

```
AVRecorder/
├── Sources/
│   ├── App/            AVRecorderApp.swift        – app entry point, wiring
│   ├── UI/             ContentView, SettingsSheet – SwiftUI interface
│   ├── Views/          CameraPreview, LevelMeter, RecordButton, StatusLabel…
│   ├── ViewModels/     RecorderViewModel.swift    – orchestrator (MainActor)
│   ├── Capture/        CameraManager, SystemAudioCapturer
│   ├── Settings/       AppSettings, AppSettingsStore
│   ├── Sync/           RecordingEngine.swift      – AVAssetWriter muxer
│   └── Permissions/    Permissions.swift
├── Resources/          Asset catalog (app icon, accent color)
└── SupportingFiles/    Info.plist, AVRecorder.entitlements
```

### The three capture/mux stages

1. **CameraManager** (`Capture/CameraManager.swift`, `@MainActor`)
   - Owns an `AVCaptureSession` running at `.hd1280x720` on the front camera.
   - Exposes `videoSampleHandler: (CMSampleBuffer, Double) -> Void` — the `Double` is a **host-time-based second offset** per frame. Frames come from `AVCaptureVideoDataOutput` on a private `videoQueue`, and the host clock is derived via `CMSyncConvertTime` from the session's `synchronizationClock`.
   - Computes `videoWriterSettings` from the output's `recommendedVideoSettingsForAssetWriter`. In **vertical** mode it width-crops the settings to a 9:16 frame and exposes `videoCropRect` (the center slice in source coordinates) — the source stays **unrotated**, and cropping happens at encode time.

2. **SystemAudioCapturer** (`Capture/SystemAudioCapturer.swift`)
   - Captures the **entire system audio mix** (not just mic input) using the Core Audio **process tap** API on macOS 14.4+.
   - `prepare()` creates a `CATapDescription(stereoGlobalTapButExcludeProcesses:)` with `isMixdown`, `isPrivate`, then builds a **private aggregate device** (`AudioHardwareCreateAggregateDevice`) whose `TapList` references that tap's UUID, and installs an IO proc via `AudioDeviceCreateIOProcIDWithBlock`.
   - **Real-time path split**: the IO proc (`pump`) runs on the real-time `ioQueue` and only copies the raw PCM `Data` plus the `mHostTime`-derived presentation seconds. Conversion to `CMSampleBuffer`, level metering, and delivery happen on the async `drainQueue` so the real-time thread is never blocked.
   - `onSampleBuffer` hands each `CMSampleBuffer` to the recorder; `onLevel` emits a smoothed RMS level (fast attack / slow release) at ~30 Hz for the UI meter.

3. **RecordingEngine** (`Sync/RecordingEngine.swift`)
   - Uses `AVAssetWriter(.mov)` with one video input (H.264 via the camera's recommended settings) and one audio input (AAC 192 kbps, source format hint from the tap).
   - **Timeline anchoring**: the first sample to arrive (from either stream, serialized on `writerQueue`) defines the anchor at `t=0` via `startSession(atSourceTime: .zero)`. Every later sample is retimed to `absoluteSeconds - anchorSeconds`, so video and audio from different sources share one start-of-file clock — this is what keeps them in sync.
   - A `pausedLock`-guarded gate drops samples before recording starts or after it stops.
   - Supports an **audio-lead offset** (`audioLeadMilliseconds`) subtracted from the audio PTS — the user-facing "Diff" tuning.
   - In vertical mode it performs a manual **center crop** through an `AVAssetWriterInputPixelBufferAdaptor`: it copies the Y plane (row by `memcpy`) and the chroma plane (half-resolution) from the source into a pooled destination buffer matching the 9:16 output size.

### The data flow / thread topology

```
                    ┌─────────────────────────────┐
   front camera ───▶│ CameraManager (videoQueue)  │──▶ hostSeconds
                    └─────────────────────────────┘        │
                                                           ▼
system audio ──────▶ SystemAudioCapturer                RecorderViewModel
   (ioQueue, rt) ──▶ (drainQueue, async) ──▶ onSampleBuffer
                                                           │
                                                           ▼
                                                  RecordingEngine
                                               (writerQueue, serial)
                                                   │
                                                   ▼
                                        AVAssetWriter → .mov
```

- Camera frames and audio samples arrive on **different queues**; `RecordingEngine` funnels both onto its single serial `writerQueue` so `AVAssetWriter` is never driven concurrently.
- The system-audio tap runs **continuously** from app launch (for the live meter) and recording simply gates which samples reach the writer — no tap restart on record.

### Recording lifecycle (`RecorderViewModel`)

- `startRecording()` reads the tap's current `availableFormat`, the camera's `videoWriterSettings`, the orientation-driven `videoCropRect`, and the diff offset, then calls `engine.startWriting(...)`.
- Output is written to a **temp UUID-named file** first, because the final name carries the end timestamp. On `stop()`, `engine.finish` finalizes the writer and the file is renamed to `AVRecorder-yyyyMMdd-HHmmss.mov` in the chosen save folder.
- `cancel()` aborts without emitting a file.

### Settings & persistence

- `AppSettings` is a plain value struct (`resolution`, `frameRate`, `orientation`, `savePath`, `diff`).
- `AppSettingsStore` (`@MainActor`, Combine) persists it to `UserDefaults` under `settings.*` keys and restores on launch (with legacy save-path migration).
- Note: `resolution` and `frameRate` are currently **displayed in the UI but not yet wired into the camera/writer** — the session is hardcoded to 720p and the writer uses the camera's recommended settings. `orientation` and `diff` are the effective knobs today.

### Permissions & entitlements

- Supported: **not sandboxed**, but the `AVRecorder.entitlements` still declare camera + audio-input + user-selected read-write for future sandboxing.
- `Info.plist` carries usage strings for camera, microphone, `NSSystemAudioRecording`, and `NSAudioCapture`.
- `Permissions.swift` fully implements camera authorization; system-audio status/request currently return `.notDetermined` — system audio permission is actually triggered implicitly on the first `prepare()`/`start()` of the tap.

### Known behaviors / gotchas

- **Requires macOS 14.4+** for `AudioHardwareCreateProcessTap` / `AudioDeviceCreateIOProcIDWithBlock`.
- The process tap can only be created on a **non-sandboxed** app in practice (aggregate device creation is restricted under sandbox).
- Vertical mode crops at encode time rather than rotating, so the source buffer is never rotated.
- If the camera provider or writer configuration throws, recording is cancelled and no (partial) file is left behind.
