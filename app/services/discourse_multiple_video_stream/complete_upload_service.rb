# frozen_string_literal: true

module DiscourseMultipleVideoStream
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
      if Config.provider == "hovod"
        finalize_hovod_upload(params.video_id)
      else
        { success: true, video_id: params.video_id }
      end
    end

    def finalize_hovod_upload(video_id)
      api_url = Config.hovod_api_url
      api_key = Config.hovod_api_key

      if api_url.blank? || api_key.blank?
        context.fail!(error: I18n.t("multiple_video_stream.errors.misconfigured"), status: 422)
      end

      headers = {
        "Authorization" => "Bearer #{api_key}",
        "Content-Type" => "application/json",
        "Accept" => "application/json",
      }
      if Config.hovod_organization_id.present?
        headers["x-organization-id"] = Config.hovod_organization_id
      end

      # 1. Mark upload complete on Hovod
      complete_res = Faraday.post("#{api_url}/v1/assets/#{video_id}/upload-complete", nil, headers) do |req|
        req.options.timeout = FARADAY_TIMEOUT
        req.options.open_timeout = FARADAY_OPEN_TIMEOUT
      end

      if complete_res.status >= 400
        Rails.logger.warn("[MultipleVideoStream] Hovod upload-complete returned #{complete_res.status}: #{complete_res.body}")
      end

      # 2. Trigger processing / transcoding
      process_res = Faraday.post("#{api_url}/v1/assets/#{video_id}/process", {}.to_json, headers) do |req|
        req.options.timeout = FARADAY_TIMEOUT
        req.options.open_timeout = FARADAY_OPEN_TIMEOUT
      end

      if process_res.status >= 400 && process_res.status != 409
        Rails.logger.warn("[MultipleVideoStream] Hovod process returned #{process_res.status}: #{process_res.body}")
      end

      { success: true, video_id: video_id }
    rescue Faraday::Error => error
      Rails.logger.error("[MultipleVideoStream] Complete upload error: #{error.class}: #{error.message}")
      { success: true, video_id: video_id }
    end
  end
end
