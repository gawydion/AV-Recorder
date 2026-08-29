# Development First Steps – Phase 1 Setup

**Last updated:** 2026-08-07  
**Related files:** `architecture.md`, `dev-plan.md`

---

## Quick Answers

| Question | Answer |
|----------|--------|
| Do I need Xcode locally? | **Yes.** Native Swift/SwiftUI Mac apps can only be built and run with Xcode on a Mac. |
| Do I need to pay anything? | **No** for development and testing on your own machine. Xcode is free. A free Apple ID is enough. |
| When would I need to pay? | Only later if you want to distribute the app to other people (App Store, or notarized outside the App Store). That requires the Apple Developer Program ($99/year). You can ignore this for now. |

---

## First Steps – Starting Phase 1 (Skeleton UI)

Do these on your MacBook:

### 1. Install / Update Xcode
1. Open the **Mac App Store**.
2. Search for **Xcode** and install (or update) it.
3. After installation, open Xcode once and let it install the additional components it asks for.
4. Make sure you are signed in with your Apple ID  
   (Xcode → Settings → Accounts → add your Apple ID if it’s not there).

### 2. Create the Project
1. Open Xcode → **File → New → Project…**
2. Choose **macOS** → **App**
3. Fill in:
   - **Product Name**: something like `GuitarRecorder` or `NeuralCam`
   - **Team**: your personal team (free Apple ID)
   - **Organization Identifier**: e.g. `com.yourname`
   - **Interface**: **SwiftUI**
   - **Language**: **Swift**
   - Uncheck “Include Tests” for now (you can add later)
4. Choose a location and create the project.

### 3. Set the Deployment Target
1. Select the project in the left navigator.
2. Select the app target.
3. Under **General** → **Minimum Deployments**, set **macOS** to **14.2** (or higher if you prefer).

This matches our architecture (Core Audio Process Taps require 14.2+).

### 4. First Runnable Skeleton
Replace the default `ContentView` with a simple layout that already looks like the final app:

- Large camera preview area (use a colored `Rectangle` or `Text("Camera Preview")` for now)
- Audio level meter area (placeholder bars or text)
- Big **Record** / **Stop** / **Pause** buttons
- Status text with clear states: Idle → Recording… → Paused
- A simple toolbar or button that opens a settings sheet (even if the settings do nothing yet)

Goal of this step: when you press ⌘R the app launches with the visual structure of the final product.

---

## What You Should Have at the End of These Steps
- A project that builds and runs
- A window that already has the basic UI layout of the finished app
- Record / Stop / Pause buttons that can at least change the status text through Idle → Recording… → Paused
- Ready for Phase 2 (real camera)
