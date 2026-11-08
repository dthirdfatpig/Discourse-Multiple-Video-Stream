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

    def build_hovod_connection(api_url)
      Faraday.new(url: api_url) do |conn|
        conn.options.timeout = FARADAY_TIMEOUT
        conn.options.open_timeout = FARADAY_OPEN_TIMEOUT
        if api_url.match?(%r{^https://(?:\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|localhost|127\.)})
          conn.ssl.verify = false
        end
        conn.adapter Faraday.default_adapter
      end
    end

    def hovod_headers(api_key)
      h = {
        "Content-Type" => "application/json",
        "Accept" => "application/json",
      }
      h["X-Api-Key"] = api_key
      h["Authorization"] = "Bearer #{api_key}"
      if Config.hovod_organization_id.present?
        h["x-organization-id"] = Config.hovod_organization_id
      end
      h
    end

    def finalize_hovod_upload(video_id)
      api_url = Config.hovod_api_url
      api_key = Config.hovod_api_key

      if api_url.blank? || api_key.blank?
        context.fail!(error: I18n.t("multiple_video_stream.errors.misconfigured"), status: 422)
      end

      headers = hovod_headers(api_key)
      client = build_hovod_connection(api_url)

      # 1. Mark upload complete on Hovod
      begin
        complete_res = client.post("/v1/assets/#{video_id}/upload-complete", nil, headers)
        if complete_res.status >= 400
          Rails.logger.warn("[MultipleVideoStream] Hovod upload-complete returned #{complete_res.status}: #{complete_res.body}")
        end
      rescue => e
        Rails.logger.warn("[MultipleVideoStream] Hovod upload-complete exception: #{e.message}")
      end

      # 2. Trigger processing / transcoding
      begin
        process_res = client.post("/v1/assets/#{video_id}/process", {}.to_json, headers)
        if process_res.status >= 400 && process_res.status != 409
          Rails.logger.warn("[MultipleVideoStream] Hovod process returned #{process_res.status}: #{process_res.body}")
        end
      rescue => e
        Rails.logger.warn("[MultipleVideoStream] Hovod process exception: #{e.message}")
      end

      { success: true, video_id: video_id }
    rescue Faraday::Error => error
      Rails.logger.error("[MultipleVideoStream] Complete upload error: #{error.class}: #{error.message}")
      { success: true, video_id: video_id }
    end
  end
end
