# Pause&PlayHere

An open-source, offline-first Windows media player built with Flutter, `libmpv`, and `FFmpeg`.

## Features
- **Instant Speed Boost:** Hold Spacebar, `S`, or Left Mouse Click for `2.0x` speed; tap Right Arrow while holding to climb to `3.0x → 4.0x → 5.0x`.
- **Zero-Lag 4K/8K Seeking:** Keyframe-accelerated seeking with RAM buffering.
- **Desktop & Touch Gestures:** Vertical left-side brightness drag, right-side volume drag (up to 200% boost), double-click `±10s` seek, and screen lock (`L`).
- **Audio & Video Engine:** Hardware GPU decoding (`HW+`), instant subtitle switching, audio track switcher, built-in equalizer presets, network stream URL playback, and HDMI bitstream passthrough.
- **Built-in User Guide:** Press `G` or `F1` anytime inside the player.

## Privacy & Licensing
- **Privacy:** 100% offline-first—zero telemetry, tracking, or data collection. See [PRIVACY.md](PRIVACY.md).
- **License:** MIT License ([LICENSE](LICENSE)). Dynamically links open-source FFmpeg (LGPLv3) and libmpv (LGPLv2.1+) libraries—see [NOTICE.md](NOTICE.md).
