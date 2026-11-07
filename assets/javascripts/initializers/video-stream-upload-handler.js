import { withPluginApi } from "discourse/lib/plugin-api";
import { UploadPreProcessorPlugin } from "discourse/lib/uppy-plugin-base";
import VideoUploadModal from "../discourse/components/modal/video-upload-modal";

const BYTES_IN_MEGABYTE = 1_000_000;

function isEnabled(siteSettings) {
  return Boolean(
    siteSettings.multiple_video_stream_enabled ||
      siteSettings.video_stream_enabled
  );
}

function shouldIntercept(siteSettings) {
  if (siteSettings.multiple_video_stream_intercept_native_uploads !== undefined) {
    return Boolean(siteSettings.multiple_video_stream_intercept_native_uploads);
  }
  return Boolean(siteSettings.video_stream_intercept_native_uploads);
}

function getProvider(siteSettings) {
  const p =
    siteSettings.multiple_video_stream_provider ||
    siteSettings.video_stream_provider ||
    "Cloudflare";
  return String(p).trim().toLowerCase();
}

/**
 * Check if a file should be intercepted and uploaded to the streaming service
 * @param {File} file
 * @param {object} siteSettings
 * @returns {boolean}
 */
function shouldInterceptUpload(file, siteSettings) {
  if (!isEnabled(siteSettings)) {
    return false;
  }

  if (!shouldIntercept(siteSettings)) {
    return false;
  }

  const provider = getProvider(siteSettings);
  if (provider === "bunny") {
    const lib =
      siteSettings.multiple_video_stream_bunny_library_id ||
      siteSettings.video_stream_bunny_library_id;
    const host =
      siteSettings.multiple_video_stream_bunny_hostname ||
      siteSettings.video_stream_bunny_hostname;
    if (!lib || !host) {
      return false;
    }
  } else if (provider === "hovod") {
    const url =
      siteSettings.multiple_video_stream_hovod_api_url ||
      siteSettings.video_stream_hovod_api_url;
    if (!url) {
      return false;
    }
  } else {
    const sub =
      siteSettings.multiple_video_stream_customer_subdomain ||
      siteSettings.video_stream_customer_subdomain;
    if (!sub) {
      return false;
    }
  }

  const thresholdMb =
    Number(
      siteSettings.multiple_video_stream_intercept_threshold_mb ||
        siteSettings.video_stream_intercept_threshold_mb
    ) || 0;
  const thresholdBytes = thresholdMb * BYTES_IN_MEGABYTE;

  return (file.size || 0) >= thresholdBytes;
}

/**
 * Get allowed video extensions from site settings
 * @param {object} siteSettings
 * @returns {string[]}
 */
function getAllowedExtensions(siteSettings) {
  const exts =
    siteSettings.multiple_video_stream_allowed_extensions ||
    siteSettings.video_stream_allowed_extensions;
  return (
    exts
      ?.split(",")
      .map((ext) => ext.trim().toLowerCase())
      .filter(Boolean) ?? []
  );
}

/**
 * Check if a file matches allowed video extensions
 * @param {object} file
 * @param {object} siteSettings
 * @returns {boolean}
 */
function isMatchingVideo(file, siteSettings) {
  const extensions = getAllowedExtensions(siteSettings);
  if (!extensions.length) {
    return false;
  }
  const name = file.name || "";
  const match = name.match(/\.([a-zA-Z0-9]+)$/);
  if (!match) {
    return false;
  }
  return extensions.includes(match[1].toLowerCase());
}

/**
 * Preprocessor that intercepts video uploads meeting or exceeding the threshold
 * and redirects them to the video stream modal, while letting smaller videos
 * pass through to Discourse's native upload pipeline without hanging.
 */
class VideoStreamUploadPreProcessor extends UploadPreProcessorPlugin {
  static pluginId = "multiple-video-stream-upload-preprocessor";

  constructor(uppy, opts) {
    super(uppy, opts);
    this.composerModel = opts.composerModel;
    this.siteSettings = opts.siteSettings;
    this.modal = opts.modal;
    this.appEvents = opts.appEvents;
    this._processFiles = this._processFiles.bind(this);
  }

  install() {
    this.uppy.addPreProcessor(this._processFiles);
  }

  uninstall() {
    this.uppy.removePreProcessor(this._processFiles);
  }

  _emitComplete(file, passThrough = false) {
    if (!passThrough) {
      this.uppy.emit("preprocess-progress", file, {
        mode: "determinate",
        message: "video_stream.upload_progress",
        value: 1,
      });
    }

    this.uppy.emit("preprocess-complete", file);
    return Promise.resolve();
  }

  _processFiles(fileIDs) {
    const promises = fileIDs.map((fileID) => {
      const file = this.uppy.getFile(fileID);
      if (!file) {
        return Promise.resolve();
      }

      if (
        isMatchingVideo(file, this.siteSettings) &&
        shouldInterceptUpload(file.data, this.siteSettings)
      ) {
        // Remove intercepted file from Uppy queue so native upload does not trigger
        this.uppy.removeFile(fileID);

        // Open modal preloaded with intercepted file
        this.modal.show(VideoUploadModal, {
          model: {
            toolbarEvent: {
              addText: (text) => {
                const composer = this.composerModel;
                if (composer) {
                  composer.appendMarkdown(text);
                }
              },
            },
            preselectedFile: file.data,
          },
        });

        return this._emitComplete(file, false);
      }

      // Allow file to continue through normal upload pipeline
      return this._emitComplete(file, true);
    });

    return Promise.all(promises);
  }
}

function initializeVideoUploadHandler(api) {
  const siteSettings = api.container.lookup("service:site-settings");
  const modal = api.container.lookup("service:modal");
  const appEvents = api.container.lookup("service:app-events");

  if (api.addComposerUploadPreProcessor) {
    api.addComposerUploadPreProcessor(
      VideoStreamUploadPreProcessor,
      ({ composerModel }) => {
        return {
          composerModel,
          siteSettings,
          modal,
          appEvents,
        };
      }
    );
  }
}

export default {
  name: "multiple-video-stream-upload-handler",
  initialize() {
    withPluginApi(initializeVideoUploadHandler);
  },
};
