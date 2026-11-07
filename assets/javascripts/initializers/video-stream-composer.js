import { withPluginApi } from "discourse/lib/plugin-api";
import LiveStreamModal from "../discourse/components/modal/live-stream-modal";
import VideoUploadModal from "../discourse/components/modal/video-upload-modal";

function isEnabled(siteSettings) {
  return Boolean(
    siteSettings.multiple_video_stream_enabled ||
      siteSettings.video_stream_enabled
  );
}

function getProvider(siteSettings) {
  const p =
    siteSettings.multiple_video_stream_provider ||
    siteSettings.video_stream_provider ||
    "Cloudflare";
  return String(p).trim().toLowerCase();
}

function isProviderConfigured(siteSettings) {
  if (!isEnabled(siteSettings)) {
    return false;
  }

  const provider = getProvider(siteSettings);
  if (provider === "bunny") {
    return Boolean(
      (siteSettings.multiple_video_stream_bunny_library_id ||
        siteSettings.video_stream_bunny_library_id) &&
        (siteSettings.multiple_video_stream_bunny_hostname ||
          siteSettings.video_stream_bunny_hostname)
    );
  }
  if (provider === "hovod") {
    return Boolean(
      siteSettings.multiple_video_stream_hovod_api_url ||
        siteSettings.video_stream_hovod_api_url
    );
  }

  return Boolean(
    siteSettings.multiple_video_stream_customer_subdomain ||
      siteSettings.video_stream_customer_subdomain
  );
}

function initializeVideoUploader(api) {
  const modal = api.container.lookup("service:modal");
  const siteSettings = api.container.lookup("service:site-settings");

  api.addComposerToolbarPopupMenuOption({
    icon: "video",
    label: "multiple_video_stream.upload_video",
    action: (toolbarEvent) => {
      modal.show(VideoUploadModal, {
        model: {
          toolbarEvent,
        },
      });
    },
    condition: () => isProviderConfigured(siteSettings),
  });

  api.addComposerToolbarPopupMenuOption({
    icon: "tower-broadcast",
    label: "multiple_video_stream.create_live_stream",
    action: (toolbarEvent) => {
      modal.show(LiveStreamModal, {
        model: {
          toolbarEvent,
        },
      });
    },
    condition: () => {
      const provider = getProvider(siteSettings);
      const liveStreamsEnabled = Boolean(
        siteSettings.multiple_video_stream_enable_live_streams ||
          siteSettings.video_stream_enable_live_streams
      );
      return (
        isProviderConfigured(siteSettings) &&
        liveStreamsEnabled &&
        provider !== "hovod"
      );
    },
  });
}

export default {
  name: "multiple-video-stream-composer",
  initialize() {
    withPluginApi(initializeVideoUploader);
  },
};
