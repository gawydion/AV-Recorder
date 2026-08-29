# Mac Guitar Recording App – Development Plan

**Last updated:** 2026-08-07 (status states clarified)  
**Aligned with:** `architecture.md`  
**Approach:** Incremental, runnable milestones. Each phase produces a working app that can be tested before moving to the next.

---

## Phase 1 – Skeleton UI + Project Foundation

**Goal:** A runnable Mac app with the basic visual structure and navigation, ready for capture features to be plugged in.

### Deliverables
- Xcode project (Swift + SwiftUI, macOS 14.2+ deployment target)
- Main window layout:
  - Large camera preview area (placeholder for now)
  - Audio level meter area (placeholder)
  - Record / Stop / Pause buttons
  - Status text with clear states: Idle → Recording… → Paused
  - Simple settings panel or sheet (resolution, frame rate, sample rate, orientation, audio source – non-functional yet)
- Basic app lifecycle and window management
- Permission request scaffolding (Camera + System Audio Recording) – can be stubbed
- Clean folder structure reflecting the architecture (UI / Capture / Sync / etc.)

### Done when
- App launches cleanly on macOS 14.2+
- UI looks like the final product (even if most controls do nothing)
- You can click Record / Stop / Pause and see the status text cycle through Idle → Recording… → Paused
- Project builds without warnings related to structure

---

## Phase 2 – Video Capture + Video-Only Recording

**Goal:** Live front-camera preview and the ability to record video-only files.

### Deliverables
- `VideoCapture` component using `AVCaptureSession`
  - Select built-in front camera
  - Deliver live frames to the SwiftUI preview
  - Produce timed `CMSampleBuffer`s
- Start/stop camera session cleanly (handle interruptions, permissions)
- Video-only recording path using `AVAssetWriter`
  - Write H.264 (or HEVC) video track
  - Save .mov / .mp4 to a known location
- Basic error handling and status updates in the UI
- Camera permission request and graceful denial handling

### Done when
- Live front-camera preview works
- Pressing Record starts writing a video file
- Pressing Stop finalizes a playable .mov/.mp4 that contains only video
- Preview continues to work after recording
- App does not crash on permission denial or camera unavailability

---

## Phase 3 – System Audio Capture + Audio-Only Recording

**Goal:** Capture system audio via Core Audio Process Taps and record it as a standalone audio file.

### Deliverables
- `AudioCapture` component using Core Audio Process Taps
  - Create `CATapDescription` (start with global stereo tap)
  - Build the required aggregate device
  - Receive clean PCM buffers
  - Basic level metering from the buffers (feed the UI meters)
- Audio-only recording path
  - Write AAC (or linear PCM) using `AVAssetWriter` or `AVAudioFile`
  - Save a playable audio file
- System Audio Recording permission handling
- Ability to start/stop the tap cleanly
- Simple process list or global-only mode (global first)

### Done when
- Playing music (Spotify / YouTube / etc.) is captured when the tap is active
- Level meters move in real time
- Record → Stop produces a playable audio file containing the system audio
- No ScreenCaptureKit code exists
- Tap can be started and stopped repeatedly without leaking resources

---

## Phase 4 – Synchronized Audio + Video Recording

**Goal:** Combine the two capture paths into a single synchronized movie file.

### Deliverables
- Unified recording session that owns both `VideoCapture` and `AudioCapture`
- Shared timing / master clock strategy
- Single `AVAssetWriter` with both video and audio inputs
- Correct presentation timestamp alignment so A/V stay in sync
- Start both captures as close together as possible
- Handle format conversion (sample rate, channel layout) if needed
- Final .mov / .mp4 containing both tracks, playable and in sync

### Done when
- One Record button starts both camera and system audio
- One Stop button produces a single file with video + audio
- Playing the file shows the camera image with the correct system audio underneath
- No noticeable drift over a few minutes of recording
- Neural DSP + background music (when both are playing to the speakers) appear correctly mixed in the audio track

---

## Phase 5 – Polish & Usability (v1 Complete)

**Goal:** Make the app pleasant and reliable for daily use.

### Deliverables
- Improved level meters and recording status
- Basic settings that actually work (resolution, frame rate, sample rate, orientation vertical/horizontal, audio source global vs selected processes)
- File management (choose save location, list recent takes, reveal in Finder)
- Better permission UX and first-run guidance
- Graceful handling of device changes, sleep/wake, and interruptions
- App icon and basic branding
- Simple logging for debugging capture issues

### Done when
- The full workflow feels solid: open app → see preview + meters → record guitar-over-track → stop → playable synced file
- Edge cases (permission denial, no camera, no audio, long recordings) are handled without crashing
- Ready for real-world testing with Neural DSP + Spotify/YouTube

---

## Out of Scope for This Plan (Future Work)
- Hosting Neural DSP inside the app
- Multi-track / stem recording
- Real-time monitoring path
- Editing / trimming tools
- Advanced process filtering UI
- Distribution / notarization / packaging refinements

---

## Suggested Order of Implementation

1. Phase 1 – Skeleton UI  
2. Phase 2 – Video  
3. Phase 3 – Audio  
4. Phase 4 – Sync & Mux  
5. Phase 5 – Polish  

Each phase should end with a runnable, testable build before starting the next.
