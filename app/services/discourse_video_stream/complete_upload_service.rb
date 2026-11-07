# frozen_string_literal: true

module DiscourseVideoStream
  class CompleteUploadService
    include ::Service::Base

    params do
      attribute :video_id, :string
    end

    model :result

    FARADAY_TIMEOUT = 15
    FARADAY_OPEN_TIMEOUT = 5

    private

    def fetch_result(params:)
      provider = SiteSetting.video_stream_provider.presence || "cloudflare"

      if provider == "hovod"
        finalize_hovod_upload(params.video_id)
      else
        { success: true, video_id: params.video_id }
      end
    end

    def finalize_hovod_upload(video_id)
      api_url = SiteSetting.video_stream_hovod_api_url.presence
      api_key = SiteSetting.video_stream_hovod_api_key.presence

      if api_url.blank? || api_key.blank?
        context.fail!(error: I18n.t("video_stream.errors.misconfigured"), status: 422)
      end

      clean_api_url = api_url.to_s.strip.chomp("/")
      headers = {
        "Authorization" => "Bearer #{api_key}",
        "Content-Type" => "application/json",
        "Accept" => "application/json",
      }
      if SiteSetting.video_stream_hovod_organization_id.present?
        headers["x-organization-id"] = SiteSetting.video_stream_hovod_organization_id.strip
      end

      # 1. Mark upload complete on Hovod
      complete_res = Faraday.post("#{clean_api_url}/v1/assets/#{video_id}/upload-complete", nil, headers) do |req|
        req.options.timeout = FARADAY_TIMEOUT
        req.options.open_timeout = FARADAY_OPEN_TIMEOUT
      end

      if complete_res.status >= 400
        Rails.logger.warn("[VideoStream] Hovod upload-complete returned #{complete_res.status}: #{complete_res.body}")
      end

      # 2. Trigger processing / transcoding
      process_res = Faraday.post("#{clean_api_url}/v1/assets/#{video_id}/process", {}.to_json, headers) do |req|
        req.options.timeout = FARADAY_TIMEOUT
        req.options.open_timeout = FARADAY_OPEN_TIMEOUT
      end

      if process_res.status >= 400 && process_res.status != 409
        Rails.logger.warn("[VideoStream] Hovod process returned #{process_res.status}: #{process_res.body}")
      end

      { success: true, video_id: video_id }
    rescue Faraday::Error => error
      Rails.logger.error("[VideoStream] Complete upload error: #{error.class}: #{error.message}")
      { success: true, video_id: video_id }
    end
  end
end
