# Changelog

All notable changes to the `Multiple Video Stream` plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.0.1.beta] - 2026-11-07

### Added
- **Hovod Video Streaming Integration**: Added comprehensive support for [Hovod](https://github.com/Synapsr/Hovod), an open-source self-hosted video platform with adaptive HLS transcoding and S3 delivery.
  - Video asset creation via Hovod REST API (`POST /v1/assets`).
  - Pre-signed S3 direct upload generation (`POST /v1/assets/:id/upload-url`) with real-time progress reporting.
  - Automatic upload completion verification and HLS transcode job triggering (`POST /v1/assets/:id/upload-complete` & `POST /v1/assets/:id/process`).
  - Resilient upload fallback pipeline proxied through Discourse for restricted CORS or strict network environments (`POST /video-stream/direct-upload`).
  - S3 / CDN direct HLS playback (`/playback/:id/master.m3u8`) and dynamic metadata resolution via Hovod public playback endpoint (`/v1/playback/:id`).
- **Simultaneous Multi-Provider Playback**: Shaka Player now plays videos from Cloudflare Stream, Bunny.net, and Hovod simultaneously in the same topic or post without requiring administrator configuration toggling.
- **Smart Provider Auto-Detection**: Heuristic detection prioritizing Bunny (UUID with hyphens), Cloudflare (32-character hex UID), and Hovod (12-24 character nanoid) with automatic multi-manifest fallback.
- **Hovod Configuration Settings**:
  - `video_stream_hovod_api_url`: Hovod API endpoint URL.
  - `video_stream_hovod_api_key`: Hovod API key (masked secret with `mk_` credential support).
  - `video_stream_hovod_hostname`: Hovod CDN / S3 playback hostname for HLS manifests and poster thumbnails.
  - `video_stream_hovod_organization_id`: Organization identifier for multi-tenant Hovod deployments.
- **Full Configuration Parity**: Extended existing provider settings (file size limits, allowed extensions, keep original filename, upload interception thresholds, and aspect ratio changer) to Hovod.

### Changed
- **Project Rebranding**: Project title on GitHub: "Discourse Video Stream", Discourse plugin name: "Multiple Video Stream".
- **Unchanged BBCode Syntax**: Maintained strict compatibility with existing `[video-stream id="..."][/video-stream]` BBCode syntax across all providers.
- **Initial Versioning**: Reset version history to `0.0.1.beta`.
