# frozen_string_literal: true

# name: multiple-video-stream
# about: Multi-provider video streaming plugin for Discourse integrating Cloudflare Stream, Bunny.net, and Hovod.
# meta_topic_id: TODO
# version: 0.0.1.beta
# authors: dthirdfatpig
# url: https://github.com/dthirdfatpig/Discourse-Multiple-Video-Stream
# required_version: 2.7.0

enabled_site_setting :video_stream_enabled

register_asset "stylesheets/common/video-stream.scss"

module ::DiscourseVideoStream
  PLUGIN_NAME = "multiple-video-stream"
end

require_relative "lib/discourse_video_stream/engine"

def humanized_name
  "Multiple Video Stream"
end

after_initialize do
  register_svg_icon("video")
  register_svg_icon("tower-broadcast")
end
