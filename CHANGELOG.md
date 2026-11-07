# Changelog

All notable changes to the `Multiple Video Stream` plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.0.2.beta] - 2026-11-07

### Fixed
- **Discourse Admin Settings Page**: Resolved issue where Discourse did not display the plugin settings page by aligning plugin metadata name to `discourse-multiple-video-stream`, overriding `plugin_settings` and `any_settings?` on the plugin instance, and ensuring settings mappings in `SiteSetting.plugins` handle directory name casing and query filter aliases.
- **Provider Names Capitalization**: Ensured provider choices strictly start with capital letters (`Cloudflare`, `Bunny`, `Hovod`) in settings enum and throughout frontend selection modals with case-insensitive normalization.
- **Permanent Server Connection Visibility**: Kept all provider server connection settings (Hovod API URL/IP, API key, hostname, organization ID; Cloudflare account ID, token, subdomain; Bunny library ID, API key, hostname) permanently visible in Discourse Admin Settings without conditional hiding.
- **Independent Plugin Toggle**: Fully isolated the plugin under `enabled_site_setting :multiple_video_stream_enabled` and `multiple_video_stream_*` site settings to eliminate toggle conflicts with the original `discourse-video-stream` plugin.

---

## [0.0.1.beta] - 2026-11-07

### Added
- **Hovod Video Streaming Integration**: Added comprehensive support for [Hovod](https://github.com/Synapsr/Hovod), an open-source self-hosted video platform with adaptive HLS transcoding and S3 delivery:
  - Video asset creation via Hovod REST API (`POST /v1/assets`).
  - Pre-signed S3 direct upload generation (`POST /v1/assets/:id/upload-url`) with real-time progress reporting.
  - Automatic upload completion verification and HLS transcode job triggering (`POST /v1/assets/:id/upload-complete` & `POST /v1/assets/:id/process`).
  - Resilient upload fallback pipeline proxied through Discourse for restricted CORS or strict network environments (`POST /multiple-video-stream/direct-upload`).
  - S3 / CDN direct HLS playback (`/playback/:id/master.m3u8`) and dynamic metadata resolution via Hovod public playback endpoint (`/v1/playback/:id`).
- **Simultaneous Multi-Provider Playback**: Shaka Player now plays videos from Cloudflare Stream, Bunny.net, and Hovod simultaneously in the same topic or post without requiring administrator configuration toggling.
- **Smart Provider Auto-Detection**: Heuristic detection prioritizing Bunny (UUID with hyphens), Cloudflare (32-character hex UID), and Hovod (12-24 character nanoid) with automatic multi-manifest fallback.
- **Full Configuration Parity**: Extended existing provider settings (file size limits, allowed extensions, keep original filename, upload interception thresholds, and aspect ratio changer) to Hovod.

### Changed
- **Project Rebranding**: Project title on GitHub: "Discourse Multiple Video Stream", Discourse plugin name: "Multiple Video Stream".
- **Unchanged BBCode Syntax**: Maintained strict compatibility with existing `[video-stream id="..."][/video-stream]` BBCode syntax across all providers.
- **Initial Versioning**: Initial beta release on version `0.0.1.beta`.
