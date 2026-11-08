# frozen_string_literal: true

# name: discourse-multiple-video-stream
# about: Multi-provider video streaming plugin for Discourse integrating Cloudflare Stream, Bunny.net, and Hovod.
# meta_topic_id: TODO
# version: 0.0.4.beta
# authors: dthirdfatpig
# url: https://github.com/dthirdfatpig/Discourse-Multiple-Video-Stream
# required_version: 2.7.0

enabled_site_setting :multiple_video_stream_enabled

register_asset "stylesheets/common/video-stream.scss"

module ::DiscourseMultipleVideoStream
  PLUGIN_NAME = "discourse-multiple-video-stream"
end

require_relative "lib/discourse_multiple_video_stream/engine"
require_relative "lib/discourse_multiple_video_stream/config"

unless defined?(::DiscourseVideoStream)
  ::DiscourseVideoStream = ::DiscourseMultipleVideoStream
end

def humanized_name
  "Multiple Video Stream"
end

# List of plugin settings defined in config/settings.yml
PLUGIN_SETTING_NAMES = %i[
  multiple_video_stream_enabled
  multiple_video_stream_provider
  multiple_video_stream_hovod_api_url
  multiple_video_stream_hovod_api_key
  multiple_video_stream_hovod_hostname
  multiple_video_stream_hovod_organization_id
  multiple_video_stream_account_id
  multiple_video_stream_api_token
  multiple_video_stream_customer_subdomain
  multiple_video_stream_bunny_library_id
  multiple_video_stream_bunny_api_key
  multiple_video_stream_bunny_hostname
  multiple_video_stream_allowed_extensions
  multiple_video_stream_max_file_size
  multiple_video_stream_max_duration
  multiple_video_stream_keep_original_name
  multiple_video_stream_intercept_native_uploads
  multiple_video_stream_intercept_threshold_mb
  multiple_video_stream_enable_live_streams
].freeze

# Clean label humanizer to avoid repeating "Multiple video stream" on every setting title
module MultipleVideoLabelFormatter
  LABEL_OVERRIDES = {
    "multiple_video_stream_enabled" => "Enable video uploads",
    "multiple_video_stream_provider" => "Streaming provider",
    "multiple_video_stream_hovod_api_url" => "Hovod API URL or server IP",
    "multiple_video_stream_hovod_api_key" => "Hovod API key",
    "multiple_video_stream_hovod_hostname" => "Hovod CDN or playback hostname",
    "multiple_video_stream_hovod_organization_id" => "Hovod organization ID",
    "multiple_video_stream_account_id" => "Cloudflare account ID",
    "multiple_video_stream_api_token" => "Cloudflare API token",
    "multiple_video_stream_customer_subdomain" => "Cloudflare customer subdomain",
    "multiple_video_stream_bunny_library_id" => "Bunny library ID",
    "multiple_video_stream_bunny_api_key" => "Bunny API key",
    "multiple_video_stream_bunny_hostname" => "Bunny CDN hostname",
    "multiple_video_stream_allowed_extensions" => "Allowed video extensions",
    "multiple_video_stream_max_file_size" => "Max file size (MB)",
    "multiple_video_stream_max_duration" => "Max video duration (seconds)",
    "multiple_video_stream_keep_original_name" => "Keep original video filename",
    "multiple_video_stream_intercept_native_uploads" => "Intercept native video uploads",
    "multiple_video_stream_intercept_threshold_mb" => "Intercept threshold (MB)",
    "multiple_video_stream_enable_live_streams" => "Enable live streaming",
  }.freeze

  def humanized_name(setting)
    str = setting.to_s
    LABEL_OVERRIDES[str] || super(setting)
  end
end

if defined?(SiteSettings::LabelFormatter)
  SiteSettings::LabelFormatter.singleton_class.prepend(MultipleVideoLabelFormatter)
end

if defined?(SiteSettingExtension)
  SiteSettingExtension.prepend(MultipleVideoLabelFormatter)
end

class MultipleVideoPluginMatcher
  def to_s
    "discourse-multiple-video-stream"
  end

  def to_str
    "discourse-multiple-video-stream"
  end

  def to_sym
    :"discourse-multiple-video-stream"
  end

  def ==(other)
    str = other.to_s.downcase.tr("-_", "")
    str == "discoursemultiplevideostream" ||
      str == "multiplevideostream" ||
      str == to_s.tr("-_", "")
  end

  def eql?(other)
    self == other
  end

  def hash
    to_s.hash
  end
end

class MultipleVideoCategoryMatcher
  def to_s
    "discourse_multiple_video_stream"
  end

  def to_str
    "discourse_multiple_video_stream"
  end

  def to_sym
    :discourse_multiple_video_stream
  end

  def ==(other)
    str = other.to_s.downcase.tr("-_", "")
    str == "discoursemultiplevideostream" ||
      str == "multiplevideostream" ||
      str == "plugins" ||
      str == to_s.tr("-_", "")
  end

  def eql?(other)
    self == other
  end

  def hash
    to_s.hash
  end
end

# Bind settings and categories so Discourse Admin shows options under both category & plugin filters
def self.sync_settings_metadata!
  return unless defined?(SiteSetting)

  plugin_matcher = MultipleVideoPluginMatcher.new
  category_matcher = MultipleVideoCategoryMatcher.new

  if SiteSetting.respond_to?(:plugins)
    PLUGIN_SETTING_NAMES.each do |s|
      SiteSetting.plugins[s] = plugin_matcher
    end
  end

  if SiteSetting.respond_to?(:categories)
    PLUGIN_SETTING_NAMES.each do |s|
      SiteSetting.categories[s] = category_matcher
    end
  end
end

sync_settings_metadata!

# Provide settings to Discourse AdminPluginSerializer
def plugin_settings
  @plugin_settings ||= SiteSetting.plugins.select do |setting, plugin_name|
    PLUGIN_SETTING_NAMES.include?(setting) ||
      ["discourse-multiple-video-stream", "Discourse-Multiple-Video-Stream", "multiple-video-stream", name, directory_name].include?(plugin_name.to_s)
  end
end

def any_settings?
  true
end

after_initialize do
  register_svg_icon("video")
  register_svg_icon("tower-broadcast")

  ::DiscourseMultipleVideoStream.sync_settings_metadata! if defined?(::DiscourseMultipleVideoStream.sync_settings_metadata!)
  sync_settings_metadata! if respond_to?(:sync_settings_metadata!)
end
