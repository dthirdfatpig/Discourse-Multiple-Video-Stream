# frozen_string_literal: true

module DiscourseMultipleVideoStream
  class Config
    class << self
      def enabled?
        return true if SiteSetting.multiple_video_stream_enabled
        return true if SiteSetting.respond_to?(:video_stream_enabled) && SiteSetting.video_stream_enabled
        false
      end

      def provider
        raw = SiteSetting.multiple_video_stream_provider.presence
        raw ||= SiteSetting.video_stream_provider.presence if SiteSetting.respond_to?(:video_stream_provider)
        (raw || "Cloudflare").to_s.strip.downcase
      end

      # Hovod settings
      def hovod_api_url
        url = SiteSetting.multiple_video_stream_hovod_api_url.presence
        url ||= SiteSetting.video_stream_hovod_api_url.presence if SiteSetting.respond_to?(:video_stream_hovod_api_url)
        return "" if url.blank?
        clean = url.to_s.strip
        clean = "http://#{clean}" unless clean.start_with?("http://", "https://")
        clean.chomp("/")
      end

      def hovod_api_key
        key = SiteSetting.multiple_video_stream_hovod_api_key.presence
        key ||= SiteSetting.video_stream_hovod_api_key.presence if SiteSetting.respond_to?(:video_stream_hovod_api_key)
        key.to_s.strip
      end

      def hovod_hostname
        host = SiteSetting.multiple_video_stream_hovod_hostname.presence
        host ||= SiteSetting.video_stream_hovod_hostname.presence if SiteSetting.respond_to?(:video_stream_hovod_hostname)
        if host.blank? && hovod_api_url.present?
          host = hovod_api_url.sub(%r{^https?://}, "")
        end
        host.to_s.strip
      end

      def hovod_organization_id
        org = SiteSetting.multiple_video_stream_hovod_organization_id.presence
        org ||= SiteSetting.video_stream_hovod_organization_id.presence if SiteSetting.respond_to?(:video_stream_hovod_organization_id)
        org.to_s.strip
      end

      # Cloudflare settings
      def cloudflare_account_id
        id = SiteSetting.multiple_video_stream_account_id.presence
        id ||= SiteSetting.video_stream_account_id.presence if SiteSetting.respond_to?(:video_stream_account_id)
        id.to_s.strip
      end

      def cloudflare_api_token
        token = SiteSetting.multiple_video_stream_api_token.presence
        token ||= SiteSetting.video_stream_api_token.presence if SiteSetting.respond_to?(:video_stream_api_token)
        token.to_s.strip
      end

      def customer_subdomain
        sub = SiteSetting.multiple_video_stream_customer_subdomain.presence
        sub ||= SiteSetting.video_stream_customer_subdomain.presence if SiteSetting.respond_to?(:video_stream_customer_subdomain)
        sub.to_s.strip
      end

      # Bunny settings
      def bunny_library_id
        lib = SiteSetting.multiple_video_stream_bunny_library_id.presence
        lib ||= SiteSetting.video_stream_bunny_library_id.presence if SiteSetting.respond_to?(:video_stream_bunny_library_id)
        lib.to_s.strip
      end

      def bunny_api_key
        key = SiteSetting.multiple_video_stream_bunny_api_key.presence
        key ||= SiteSetting.video_stream_bunny_api_key.presence if SiteSetting.respond_to?(:video_stream_bunny_api_key)
        key.to_s.strip
      end

      def bunny_hostname
        host = SiteSetting.multiple_video_stream_bunny_hostname.presence
        host ||= SiteSetting.video_stream_bunny_hostname.presence if SiteSetting.respond_to?(:video_stream_bunny_hostname)
        host.to_s.strip
      end

      # Upload and general settings
      def max_duration
        d = SiteSetting.multiple_video_stream_max_duration.presence
        d ||= SiteSetting.video_stream_max_duration.presence if SiteSetting.respond_to?(:video_stream_max_duration)
        (d || 300).to_i
      end

      def keep_original_name
        return true if SiteSetting.multiple_video_stream_keep_original_name
        return true if SiteSetting.respond_to?(:video_stream_keep_original_name) && SiteSetting.video_stream_keep_original_name
        false
      end

      def enable_live_streams
        return true if SiteSetting.multiple_video_stream_enable_live_streams
        return true if SiteSetting.respond_to?(:video_stream_enable_live_streams) && SiteSetting.video_stream_enable_live_streams
        false
      end
    end
  end
end
