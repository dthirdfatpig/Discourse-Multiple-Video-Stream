# frozen_string_literal: true

module DiscourseMultipleVideoStream
  class DirectUploadService
    include ::Service::Base

    params do
      attribute :file
      attribute :file_name, :string
      attribute :creator_id, :integer
    end

    model :upload_result

    FARADAY_TIMEOUT = 120
    FARADAY_OPEN_TIMEOUT = 10

    private

    def fetch_upload_result(params:)
      if Config.provider == "hovod"
        upload_to_hovod(params)
      else
        context.fail!(error: "Direct upload proxy is only used for Hovod", status: 400)
      end
    end

    def upload_to_hovod(params)
      file = params.file
      file_name = params.file_name.presence || (file.respond_to?(:original_filename) ? file.original_filename : "video.mp4")

      prep_context = PrepareUploadService.call(
        params: {
          file_name: file_name,
          file_size: file.respond_to?(:size) ? file.size.to_s : nil,
          file_type: file.respond_to?(:content_type) ? file.content_type : "video/mp4",
          creator_id: params.creator_id,
        },
      )

      if prep_context.failure?
        context.fail!(error: prep_context[:error], status: prep_context[:status] || 422)
      end

      details = prep_context[:upload_details]
      upload_url = details[:upload_url]
      video_id = details[:video_id]

      file_payload = file.respond_to?(:read) ? file.read : file
      content_type = file.respond_to?(:content_type) && file.content_type.present? ? file.content_type : "video/mp4"

      headers = { "Content-Type" => content_type }
      if Config.hovod_api_url.present? && upload_url.start_with?(Config.hovod_api_url)
        headers["X-Api-Key"] = Config.hovod_api_key
        headers["Authorization"] = "Bearer #{Config.hovod_api_key}"
      end

      conn = Faraday.new do |f|
        f.options.timeout = FARADAY_TIMEOUT
        f.options.open_timeout = FARADAY_OPEN_TIMEOUT
        if upload_url.match?(%r{^https://(?:\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|localhost|127\.)})
          f.ssl.verify = false
        end
        f.adapter Faraday.default_adapter
      end

      put_res = conn.put(upload_url, file_payload, headers)

      if put_res.status >= 400
        Rails.logger.error("[MultipleVideoStream] Failed to PUT direct upload to storage: status=#{put_res.status} body=#{put_res.body}")
        context.fail!(error: I18n.t("multiple_video_stream.errors.upload_url"), status: 502)
      end

      CompleteUploadService.call(params: { video_id: video_id })

      { video_id: video_id }
    rescue Faraday::Error => error
      Rails.logger.error("[MultipleVideoStream] Direct upload exception: #{error.class}: #{error.message}")
      context.fail!(error: I18n.t("multiple_video_stream.errors.upload_url"), status: 502)
    end
  end
end
