# frozen_string_literal: true

module DiscourseMultipleVideoStream
  class LiveStreamService
    include ::Service::Base

    CF_LIVE_INPUT_PATH =
      "https://api.cloudflare.com/client/v4/accounts/%{account_id}/stream/live_inputs"
    BUNNY_LIVE_PATH =
      "https://video.bunnycdn.com/library/%{library_id}/live"

    params { attribute :name, :string, default: "Discourse Live Stream" }

    model :live_input

    FARADAY_TIMEOUT = 15
    FARADAY_OPEN_TIMEOUT = 5

    private

    def fetch_live_input(params:)
      case Config.provider
      when "bunny"
        fetch_bunny_live_input(params)
      when "hovod"
        context.fail!(error: I18n.t("multiple_video_stream.errors.hovod_no_live_stream"), status: 422)
      else
        fetch_cloudflare_live_input(params)
      end
    end

    def fetch_cloudflare_live_input(params)
      account_id = Config.cloudflare_account_id
      api_token = Config.cloudflare_api_token

      if account_id.blank? || api_token.blank?
        context.fail!(error: I18n.t("multiple_video_stream.errors.misconfigured"), status: 422)
      end

      url = CF_LIVE_INPUT_PATH % { account_id: account_id }
      clean_name = sanitize_name(params.name)
      payload = { meta: { name: clean_name }, recording: { mode: "automatic" } }

      response =
        Faraday.post(
          url,
          payload.to_json,
          { "Authorization" => "Bearer #{api_token}", "Content-Type" => "application/json" },
        ) do |req|
          req.options.timeout = FARADAY_TIMEOUT
          req.options.open_timeout = FARADAY_OPEN_TIMEOUT
        end

      if response.status >= 400
        log_failure(response.status, parse_body(response.body))
        context.fail!(error: I18n.t("multiple_video_stream.errors.create_live_input"), status: 422)
      end

      body = parse_body(response.body)

      unless body.dig("result", "uid")
        log_failure(response.status, body)
        context.fail!(error: I18n.t("multiple_video_stream.errors.create_live_input"), status: 422)
      end

      result = body["result"]

      {
        uid: result["uid"],
        rtmps_url: result.dig("rtmps", "url"),
        rtmps_stream_key: result.dig("rtmps", "streamKey"),
        created: result["created"],
      }
    rescue JSON::ParserError, Faraday::Error => error
      log_exception(error)
      context.fail!(error: I18n.t("multiple_video_stream.errors.create_live_input"), status: 422)
    end

    def fetch_bunny_live_input(params)
      library_id = Config.bunny_library_id
      api_key = Config.bunny_api_key

      if library_id.blank? || api_key.blank?
        context.fail!(error: I18n.t("multiple_video_stream.errors.misconfigured"), status: 422)
      end

      url = BUNNY_LIVE_PATH % { library_id: library_id }
      clean_name = sanitize_name(params.name)
      payload = { title: clean_name }

      response =
        Faraday.post(
          url,
          payload.to_json,
          {
            "AccessKey" => api_key,
            "Content-Type" => "application/json",
            "Accept" => "application/json",
          },
        ) do |req|
          req.options.timeout = FARADAY_TIMEOUT
          req.options.open_timeout = FARADAY_OPEN_TIMEOUT
        end

      if response.status >= 400
        log_failure(response.status, parse_body(response.body))
        context.fail!(error: I18n.t("multiple_video_stream.errors.create_live_input"), status: 422)
      end

      body = parse_body(response.body)
      video_id = body["guid"].presence

      if video_id.blank?
        log_failure(response.status, body)
        context.fail!(error: I18n.t("multiple_video_stream.errors.create_live_input"), status: 422)
      end

      rtmp_key = body["streamKey"].presence || api_key
      rtmp_url = body["rtmpServerUri"].presence || "rtmp://live.bunnycdn.com/live"

      {
        uid: video_id,
        rtmps_url: rtmp_url,
        rtmps_stream_key: rtmp_key,
        created: body["createdAt"],
      }
    rescue JSON::ParserError, Faraday::Error => error
      log_exception(error)
      context.fail!(error: I18n.t("multiple_video_stream.errors.create_live_input"), status: 422)
    end

    def sanitize_name(name)
      return "Discourse Live Stream" if name.blank?

      sanitized = name.gsub(/[\x00-\x1f]/, "").strip
      sanitized.truncate(255).presence || "Discourse Live Stream"
    end

    def parse_body(raw_body)
      return {} if raw_body.blank?
      return raw_body if raw_body.is_a?(Hash) || raw_body.is_a?(Array)

      JSON.parse(raw_body)
    rescue JSON::ParserError
      { "raw" => raw_body.to_s.truncate(500) }
    end

    def log_failure(status, body)
      Rails.logger.error("[MultipleVideoStream] Failed to create live input (status=#{status}): #{body}")
    end

    def log_exception(error)
      Rails.logger.error("[MultipleVideoStream] Live input request raised #{error.class}: #{error.message}")
    end
  end
end
