# Phone Connect

A simple Windows GUI front-end for **[scrcpy](https://github.com/Genymobile/scrcpy)** + **adb** that makes mirroring and controlling your Android phone point-and-click: connect over USB, Wi‑Fi pairing code, or QR code, then mirror, record, or screenshot — no command line needed.

![platform](https://img.shields.io/badge/platform-Windows-blue) ![built on](https://img.shields.io/badge/built%20on-scrcpy-brightgreen)

---

## ⚠️ Disclaimer

**Phone Connect is a modified / wrapper project built on top of [scrcpy](https://github.com/Genymobile/scrcpy).**

It is an **independent GUI front-end** that drives the official `scrcpy.exe` and `adb.exe` — it does **not** change scrcpy's own code. This project is **not affiliated with, endorsed by, or supported by** the scrcpy project or Genymobile.

- **Official scrcpy project:** https://github.com/Genymobile/scrcpy
- All mirroring, recording, and control is performed by scrcpy; Phone Connect only provides the interface and runs the commands for you.
- scrcpy is created by **Romain Vimont (rom1v) / Genymobile** and licensed under **Apache License 2.0**. Please support the original project.

If you want the raw, official tool, download scrcpy directly from the link above.

---

## How it works

Phone Connect is a thin graphical layer over two command‑line tools that ship with scrcpy:

- **`adb.exe`** — Android Debug Bridge. Handles the connection to the phone (USB and wireless pairing/connecting) and device commands (screenshots, etc.).
- **`scrcpy.exe`** — the actual screen mirroring / recording engine.

When you click a button, the app simply builds and runs the matching `adb` or `scrcpy` command for you and shows the result:

1. **Connect** — depending on the selected mode, the app runs:
   - **USB:** `adb devices` to find a plugged‑in phone.
   - **Wi‑Fi code:** `adb pair <ip:port> <code>` then `adb connect <ip:port>`.
   - **QR code:** generates a Wireless‑Debugging pairing QR (rendered in‑app), watches `adb mdns services` for your phone to scan it, then pairs automatically.
2. **Start Mirroring** — launches `scrcpy` (with your chosen options) and shows its live output in‑app, with the mirror window hidden-console. Closing the mirror window or clicking **Stop Mirroring** ends it.
3. **Record** — runs scrcpy with `--record`, saving a timestamped `.mkv` to `recordings\`. On stop, the app waits for scrcpy to finalize the file so it isn't corrupted.
4. **Screenshot** — uses `adb shell screencap` + `adb pull` to save a PNG to `screenshots\`.
5. **Options** — the toggles map to scrcpy flags: *High resolution* (full res vs. `--max-size 1280 --video-bit-rate 4M --video-codec h264`), *No audio* (`--no-audio`), *Always on top* (`--always-on-top`), *Limit FPS* (`--max-fps=N`). These apply to both mirroring and recording.

The two panels at the bottom show a plain‑English **Activity** log (your clicks and results, color‑coded) and the raw **Live output** from scrcpy, plus a live FPS readout.

There is **no background service, telemetry, or network access** other than the optional "Check update" button, which queries the public scrcpy GitHub releases API.

---

## Features

- Three connection modes: **USB**, **Wi‑Fi pairing code**, and **QR code** (auto‑pair)
- One‑click **mirror**, **record** (`.mkv`), and **screenshot**
- Mirroring options: high/low resolution, audio on/off, always‑on‑top, FPS cap
- Hidden console — scrcpy output is captured into in‑app panels
- Auto device detection + auto‑reconnect to the last address
- **Check update / Update scrcpy** — downloads the latest official scrcpy win64 build in place
- One‑click **Add shortcut** (Desktop + Start menu)
- Native app (`PhoneConnect.exe`) — no PowerShell window, with its own icon

---

## Setup

Phone Connect needs the official scrcpy binaries to run. It does **not** bundle them.

1. **Download scrcpy** for Windows from the official releases:
   👉 https://github.com/Genymobile/scrcpy/releases
   (get the `scrcpy-win64-vX.Y.zip`) and extract it.
2. **Copy these files from this repo into that scrcpy folder** (next to `scrcpy.exe` and `adb.exe`):
   - `PhoneConnect.exe`
   - `PhoneConnect.ico`
   - `qrcode.min.js`  *(needed for the QR‑code mode)*
3. **Run `PhoneConnect.exe`.** That's it.

> On first launch, Windows SmartScreen may warn about an unknown publisher (the exe isn't code‑signed). Choose **More info → Run anyway**, or build it yourself from source (below).

### No‑compile alternative

Prefer not to use the prebuilt `.exe`? `PhoneConnect.ps1` is the original PowerShell version — drop it into the scrcpy folder and run it with PowerShell. (It behaves the same but runs inside a hidden PowerShell process.)

---

## Build from source

`PhoneConnect.cs` is a single‑file C# WinForms app. Build it with the .NET Framework compiler already on every Windows machine:

```bat
"%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe" ^
  /target:winexe /platform:anycpu /win32icon:PhoneConnect.ico ^
  /reference:System.Windows.Forms.dll /reference:System.Drawing.dll ^
  /reference:System.Core.dll /reference:System.IO.Compression.dll ^
  /reference:System.IO.Compression.FileSystem.dll ^
  /out:PhoneConnect.exe PhoneConnect.cs
```

Then place the resulting `PhoneConnect.exe` next to `scrcpy.exe` as described in **Setup**.

---

## Requirements

- Windows 10 / 11
- Official scrcpy win64 (provides `scrcpy.exe` + `adb.exe`)
- On the phone: **Developer options → USB debugging** (and **Wireless debugging** for Wi‑Fi/QR modes)

---

## Credits & licenses

- **scrcpy** — © Genymobile / Romain Vimont, licensed under **Apache‑2.0**. https://github.com/Genymobile/scrcpy
- **qrcodejs** (`qrcode.min.js`) — © David Shim, licensed under **MIT**. https://github.com/davidshimjs/qrcodejs
- **Phone Connect** (this wrapper) — licensed under **MIT** (see [LICENSE](LICENSE)).

Phone Connect redistributes none of scrcpy's binaries; you supply those from the official release.
