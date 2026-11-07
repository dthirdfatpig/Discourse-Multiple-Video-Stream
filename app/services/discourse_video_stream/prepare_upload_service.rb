# frozen_string_literal: true

require "openssl"

module DiscourseVideoStream
  class PrepareUploadService
    include ::Service::Base

    BUNNY_API_HOST = "https://video.bunnycdn.com"
    DEFAULT_MAX_DURATION_SECONDS = 300

    params do
      attribute :file_name, :string
      attribute :file_size, :string
      attribute :file_type, :string
      attribute :creator_id, :integer
    end

    model :upload_details

    FARADAY_TIMEOUT = 15
    FARADAY_OPEN_TIMEOUT = 5

    private

    def fetch_upload_details(params:)
      provider = SiteSetting.video_stream_provider.presence || "cloudflare"

      case provider
      when "bunny"
        fetch_bunny_upload_details(params)
      when "hovod"
        fetch_hovod_upload_details(params)
      else
        fetch_cloudflare_upload_details(params)
      end
    end

    def fetch_cloudflare_upload_details(params)
      account_id = SiteSetting.video_stream_account_id.presence
      api_token = SiteSetting.video_stream_api_token.presence

      if account_id.blank? || api_token.blank?
        context.fail!(error: I18n.t("video_stream.errors.misconfigured"), status: 422)
      end

      {
        provider: "cloudflare",
        endpoint: "/video-stream/upload-url.json",
      }
    end

    def fetch_bunny_upload_details(params)
      library_id = SiteSetting.video_stream_bunny_library_id.presence
      api_key = SiteSetting.video_stream_bunny_api_key.presence

      if library_id.blank? || api_key.blank?
        context.fail!(error: I18n.t("video_stream.errors.misconfigured"), status: 422)
      end

      title = extract_video_title(params.file_name)

      create_response =
        Faraday.post(
          "#{BUNNY_API_HOST}/library/#{library_id}/videos",
          { title: title }.to_json,
          {
            "AccessKey" => api_key,
            "Content-Type" => "application/json",
            "Accept" => "application/json",
          },
        ) do |req|
          req.options.timeout = FARADAY_TIMEOUT
          req.options.open_timeout = FARADAY_OPEN_TIMEOUT
        end

      if create_response.status >= 400
        log_failure(create_response.status, parse_body(create_response.body))
        context.fail!(error: I18n.t("video_stream.errors.upload_url"), status: 422)
      end

      body = parse_body(create_response.body)
      video_id = body["guid"].presence

      if video_id.blank?
        log_failure(create_response.status, body)
        context.fail!(error: I18n.t("video_stream.errors.upload_url"), status: 422)
      end

      expires = (Time.now + 24.hours).to_i
      signature_data = "#{library_id}#{api_key}#{expires}#{video_id}"
      signature = OpenSSL::Digest::SHA256.hexdigest(signature_data)

      {
        provider: "bunny",
        endpoint: "#{BUNNY_API_HOST}/tusupload",
        video_id: video_id,
        headers: {
          "AuthorizationSignature" => signature,
          "AuthorizationExpire" => expires.to_s,
          "LibraryId" => library_id.to_s,
          "VideoId" => video_id,
        },
      }
    rescue JSON::ParserError, Faraday::Error => error
      log_exception(error)
      context.fail!(error: I18n.t("video_stream.errors.upload_url"), status: 422)
    end

    def fetch_hovod_upload_details(params)
      api_url = SiteSetting.video_stream_hovod_api_url.presence
      api_key = SiteSetting.video_stream_hovod_api_key.presence

      if api_url.blank? || api_key.blank?
        context.fail!(error: I18n.t("video_stream.errors.misconfigured"), status: 422)
      end

      clean_api_url = api_url.to_s.strip.chomp("/")
      title = extract_video_title(params.file_name)

      headers = {
        "Authorization" => "Bearer #{api_key}",
        "Content-Type" => "application/json",
        "Accept" => "application/json",
      }
      if SiteSetting.video_stream_hovod_organization_id.present?
        headers["x-organization-id"] = SiteSetting.video_stream_hovod_organization_id.strip
      end

      metadata = {
        source: "discourse",
      }
      metadata[:creatorId] = params.creator_id.to_s if params.creator_id.present?

      max_duration = SiteSetting.video_stream_max_duration.presence || DEFAULT_MAX_DURATION_SECONDS
      metadata[:maxDurationSeconds] = max_duration.to_s if max_duration.present?

      create_response =
        Faraday.post(
          "#{clean_api_url}/v1/assets",
          { title: title, metadata: metadata }.to_json,
          headers,
        ) do |req|
          req.options.timeout = FARADAY_TIMEOUT
          req.options.open_timeout = FARADAY_OPEN_TIMEOUT
        end

      if create_response.status >= 400
        log_failure(create_response.status, parse_body(create_response.body))
        context.fail!(error: I18n.t("video_stream.errors.upload_url"), status: 422)
      end

      body = parse_body(create_response.body)
      asset_data = body["data"] || body
      asset_id = asset_data["id"]
      playback_id = asset_data["playbackId"]

      if asset_id.blank?
        log_failure(create_response.status, body)
        context.fail!(error: I18n.t("video_stream.errors.upload_url"), status: 422)
      end

      upload_url_response =
        Faraday.post(
          "#{clean_api_url}/v1/assets/#{asset_id}/upload-url",
          nil,
          headers,
        ) do |req|
          req.options.timeout = FARADAY_TIMEOUT
          req.options.open_timeout = FARADAY_OPEN_TIMEOUT
        end

      if upload_url_response.status >= 400
        log_failure(upload_url_response.status, parse_body(upload_url_response.body))
        context.fail!(error: I18n.t("video_stream.errors.upload_url"), status: 422)
      end

      upload_body = parse_body(upload_url_response.body)
      upload_data = upload_body["data"] || upload_body
      upload_url = upload_data["uploadUrl"]

      if upload_url.blank?
        log_failure(upload_url_response.status, upload_body)
        context.fail!(error: I18n.t("video_stream.errors.upload_url"), status: 422)
      end

      {
        provider: "hovod",
        video_id: asset_id,
        playback_id: playback_id,
        upload_url: upload_url,
        upload_method: upload_data["method"] || "PUT",
      }
    rescue JSON::ParserError, Faraday::Error => error
      log_exception(error)
      context.fail!(error: I18n.t("video_stream.errors.upload_url"), status: 422)
    end

    def extract_video_title(file_name)
      if SiteSetting.video_stream_keep_original_name && file_name.present?
        sanitized = file_name.to_s.gsub(/[\x00-\x1f]/, "").strip
        return sanitized.truncate(255) if sanitized.present?
      end

      "Discourse Video - #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
    end

    def parse_body(raw_body)
      return {} if raw_body.blank?
      return raw_body if raw_body.is_a?(Hash) || raw_body.is_a?(Array)

      JSON.parse(raw_body)
    rescue JSON::ParserError
      { "raw" => raw_body.to_s.truncate(500) }
    end

    def log_failure(status, body)
      Rails.logger.error("[VideoStream] Failed to prepare upload (status=#{status}): #{body}")
    end

    def log_exception(error)
      Rails.logger.error("[VideoStream] Prepare upload request raised #{error.class}: #{error.message}")
    end
  end
end
