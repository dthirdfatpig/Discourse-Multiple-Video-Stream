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

      put_res = Faraday.put(upload_url, file_payload, { "Content-Type" => content_type }) do |req|
        req.options.timeout = FARADAY_TIMEOUT
        req.options.open_timeout = FARADAY_OPEN_TIMEOUT
      end

      if put_res.status >= 400
        Rails.logger.error("[MultipleVideoStream] Failed to PUT direct upload to storage: status=#{put_res.status}")
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
