# frozen_string_literal: true

require "openssl"

module DiscourseMultipleVideoStream
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
      case Config.provider
      when "bunny"
        fetch_bunny_upload_details(params)
      when "hovod"
        fetch_hovod_upload_details(params)
      else
        fetch_cloudflare_upload_details(params)
      end
    end

    def fetch_cloudflare_upload_details(params)
      account_id = Config.cloudflare_account_id
      api_token = Config.cloudflare_api_token

      if account_id.blank? || api_token.blank?
        context.fail!(error: I18n.t("multiple_video_stream.errors.misconfigured"), status: 422)
      end

      {
        provider: "cloudflare",
        endpoint: "/multiple-video-stream/upload-url.json",
      }
    end

    def fetch_bunny_upload_details(params)
      library_id = Config.bunny_library_id
      api_key = Config.bunny_api_key

      if library_id.blank? || api_key.blank?
        context.fail!(error: I18n.t("multiple_video_stream.errors.misconfigured"), status: 422)
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
        context.fail!(error: I18n.t("multiple_video_stream.errors.upload_url"), status: 422)
      end

      body = parse_body(create_response.body)
      video_id = body["guid"].presence

      if video_id.blank?
        log_failure(create_response.status, body)
        context.fail!(error: I18n.t("multiple_video_stream.errors.upload_url"), status: 422)
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
      context.fail!(error: I18n.t("multiple_video_stream.errors.upload_url"), status: 422)
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
      # Hovod API keys (mk_live_...) require X-Api-Key header; also send Authorization for JWT
      h["X-Api-Key"] = api_key
      h["Authorization"] = "Bearer #{api_key}"
      if Config.hovod_organization_id.present?
        h["x-organization-id"] = Config.hovod_organization_id
      end
      h
    end

    def fetch_hovod_upload_details(params)
      api_url = Config.hovod_api_url
      api_key = Config.hovod_api_key

      if api_url.blank? || api_key.blank?
        context.fail!(error: I18n.t("multiple_video_stream.errors.misconfigured"), status: 422)
      end

      title = extract_video_title(params.file_name)
      headers = hovod_headers(api_key)

      metadata = {
        source: "discourse",
      }
      metadata[:creatorId] = params.creator_id.to_s if params.creator_id.present?

      max_duration = Config.max_duration
      metadata[:maxDurationSeconds] = max_duration.to_s if max_duration.present?

      client = build_hovod_connection(api_url)
      create_response = client.post("/v1/assets", { title: title, metadata: metadata }.to_json, headers)

      if create_response.status >= 400
        body = parse_body(create_response.body)
        log_failure(create_response.status, body)
        err_msg = body["error"].presence || I18n.t("multiple_video_stream.errors.upload_url")
        context.fail!(error: "Hovod: #{err_msg}", status: 422)
      end

      body = parse_body(create_response.body)
      asset_data = body["data"] || body
      asset_id = asset_data["id"]
      playback_id = asset_data["playbackId"]

      if asset_id.blank?
        log_failure(create_response.status, body)
        context.fail!(error: I18n.t("multiple_video_stream.errors.upload_url"), status: 422)
      end

      upload_url_response = client.post("/v1/assets/#{asset_id}/upload-url", nil, headers)

      if upload_url_response.status >= 400
        # If /upload-url endpoint fails, fall back to direct file PUT to Hovod
        upload_url = "#{api_url}/v1/assets/#{asset_id}/upload"
        return {
          provider: "hovod",
          video_id: asset_id,
          playback_id: playback_id,
          upload_url: upload_url,
          upload_method: "PUT",
        }
      end

      upload_body = parse_body(upload_url_response.body)
      upload_data = upload_body["data"] || upload_body
      upload_url = upload_data["uploadUrl"]

      if upload_url.blank?
        upload_url = "#{api_url}/v1/assets/#{asset_id}/upload"
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
      context.fail!(error: "Hovod: #{error.message}", status: 422)
    end

    def extract_video_title(file_name)
      if Config.keep_original_name && file_name.present?
        sanitized = file_name.to_s.gsub(/[\x00-\x1f]/, "").strip
        return sanitized.truncate(255) if sanitized.present?
      end

      "Discourse Upload #{Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')}"
    end

    def parse_body(body)
      return {} if body.blank?
      JSON.parse(body)
    rescue JSON::ParserError
      { "raw" => body }
    end

    def log_failure(status, body)
      Rails.logger.error("[MultipleVideoStream] Failed to prepare upload (status=#{status}): #{body}")
    end

    def log_exception(error)
      Rails.logger.error("[MultipleVideoStream] Prepare upload request raised #{error.class}: #{error.message}")
    end
  end
end
