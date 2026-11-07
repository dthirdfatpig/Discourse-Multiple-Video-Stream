import { withPluginApi } from "discourse/lib/plugin-api";
import LiveStreamModal from "../discourse/components/modal/live-stream-modal";
import VideoUploadModal from "../discourse/components/modal/video-upload-modal";

function isProviderConfigured(siteSettings) {
  if (!siteSettings.video_stream_enabled) {
    return false;
  }

  const provider = siteSettings.video_stream_provider || "cloudflare";
  if (provider === "bunny") {
    return Boolean(
      siteSettings.video_stream_bunny_library_id &&
      siteSettings.video_stream_bunny_hostname
    );
  }
  if (provider === "hovod") {
    return Boolean(
      siteSettings.video_stream_hovod_api_url &&
      siteSettings.video_stream_hovod_hostname
    );
  }

  return Boolean(siteSettings.video_stream_customer_subdomain);
}

function initializeVideoUploader(api) {
  const modal = api.container.lookup("service:modal");
  const siteSettings = api.container.lookup("service:site-settings");

  api.addComposerToolbarPopupMenuOption({
    icon: "video",
    label: "video_stream.upload_video",
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
    label: "video_stream.create_live_stream",
    action: (toolbarEvent) => {
      modal.show(LiveStreamModal, {
        model: {
          toolbarEvent,
        },
      });
    },
    condition: () => {
      const provider = siteSettings.video_stream_provider || "cloudflare";
      return (
        isProviderConfigured(siteSettings) &&
        siteSettings.video_stream_enable_live_streams &&
        provider !== "hovod"
      );
    },
  });
}

export default {
  name: "video-stream-composer",
  initialize() {
    withPluginApi(initializeVideoUploader);
  },
};
