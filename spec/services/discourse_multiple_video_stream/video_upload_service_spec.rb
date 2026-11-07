# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseMultipleVideoStream::VideoUploadService do
  let(:account_id) { "abc123" }
  let(:api_token) { "shhh" }
  let(:service_params) do
    {
      upload_length: "10485760",
      upload_metadata: "name ZmlsZS5tcDQ=",
      tus_resumable: "1.0.0",
      creator_id: 1,
    }
  end

  before do
    SiteSetting.multiple_video_stream_provider = "Cloudflare"
    SiteSetting.multiple_video_stream_account_id = account_id
    SiteSetting.multiple_video_stream_api_token = api_token
  end

  describe ".call" do
    it "fails when required credentials are missing" do
      SiteSetting.multiple_video_stream_api_token = ""

      context = described_class.call(params: service_params)

      expect(context.failure?).to eq(true)
      expect(context[:error]).to eq(I18n.t("multiple_video_stream.errors.misconfigured"))
      expect(context[:status]).to eq(422)
    end

    it "returns upload details when Cloudflare succeeds" do
      SiteSetting.multiple_video_stream_max_duration = 600

      headers = {
        "Location" => "https://upload.videodelivery.net/tus/abc123",
        "stream-media-id" => "abc123",
        "tus-resumable" => "1.0.0",
      }
      response = instance_double(Faraday::Response, status: 201, body: nil, headers: headers)
      allow(Faraday).to receive(:post).and_return(response)

      context = described_class.call(params: service_params)

      expect(context.success?).to eq(true)
      expect(context[:upload_details]).to include(
        upload_url: "https://upload.videodelivery.net/tus/abc123",
        stream_media_id: "abc123",
        tus_resumable: "1.0.0",
      )
      expect(Faraday).to have_received(:post).with(
        format(described_class::CF_API_PATH, account_id: account_id),
        nil,
        hash_including(
          "Authorization" => "Bearer #{api_token}",
          "Upload-Length" => service_params[:upload_length],
          "Upload-Metadata" => include(Base64.strict_encode64("600")),
        ),
      )
    end

    it "maps filename to name when keep_original_name is enabled" do
      SiteSetting.multiple_video_stream_keep_original_name = true

      headers = {
        "Location" => "https://upload.videodelivery.net/tus/abc123",
        "stream-media-id" => "abc123",
        "tus-resumable" => "1.0.0",
      }
      response = instance_double(Faraday::Response, status: 201, body: nil, headers: headers)
      allow(Faraday).to receive(:post).and_return(response)

      params = service_params.merge(upload_metadata: "filename ZmlsZS5tcDQ=")
      context = described_class.call(params: params)

      expect(context.success?).to eq(true)
      expect(Faraday).to have_received(:post).with(
        format(described_class::CF_API_PATH, account_id: account_id),
        nil,
        hash_including(
          "Upload-Metadata" => include("name ZmlsZS5tcDQ="),
        ),
      )
    end

    it "fails when Cloudflare returns an error" do
      response =
        instance_double(
          Faraday::Response,
          status: 500,
          body: { "success" => false }.to_json,
          headers: {},
        )
      allow(Faraday).to receive(:post).and_return(response)

      context = described_class.call(params: service_params)

      expect(context.failure?).to eq(true)
      expect(context[:error]).to eq(I18n.t("multiple_video_stream.errors.upload_url"))
      expect(Faraday).to have_received(:post)
    end

    context "when provider is Bunny" do
      let(:library_id) { "12345" }
      let(:api_key) { "bunny-api-key" }

      before do
        SiteSetting.multiple_video_stream_provider = "Bunny"
        SiteSetting.multiple_video_stream_bunny_library_id = library_id
        SiteSetting.multiple_video_stream_bunny_api_key = api_key
      end

      it "fails when required Bunny credentials are missing" do
        SiteSetting.multiple_video_stream_bunny_api_key = ""

        context = described_class.call(params: service_params)

        expect(context.failure?).to eq(true)
        expect(context[:error]).to eq(I18n.t("multiple_video_stream.errors.misconfigured"))
        expect(context[:status]).to eq(422)
      end

      it "creates video and returns signed upload details for Bunny" do
        create_response =
          instance_double(
            Faraday::Response,
            status: 200,
            body: { "guid" => "video-guid-123" }.to_json,
            headers: {},
          )

        allow(Faraday).to receive(:post).with(
          "https://video.bunnycdn.com/library/#{library_id}/videos",
          anything,
          hash_including("AccessKey" => api_key),
        ).and_return(create_response)

        context = described_class.call(params: service_params)

        expect(context.success?).to eq(true)
        expect(context[:upload_details]).to include(
          upload_url: "https://video.bunnycdn.com/tusupload",
          stream_media_id: "video-guid-123",
          tus_resumable: "1.0.0",
        )
        expect(context[:upload_details][:extra_headers]).to include(
          "LibraryId" => library_id,
          "VideoId" => "video-guid-123",
        )
      end
    end

    context "when provider is Hovod" do
      let(:api_url) { "https://hovod.example.com" }
      let(:api_key) { "mk_test_key" }

      before do
        SiteSetting.multiple_video_stream_provider = "Hovod"
        SiteSetting.multiple_video_stream_hovod_api_url = api_url
        SiteSetting.multiple_video_stream_hovod_api_key = api_key
      end

      it "fails when Hovod credentials are missing" do
        SiteSetting.multiple_video_stream_hovod_api_key = ""

        context = described_class.call(params: service_params)

        expect(context.failure?).to eq(true)
        expect(context[:error]).to eq(I18n.t("multiple_video_stream.errors.misconfigured"))
        expect(context[:status]).to eq(422)
      end

      it "creates asset and returns upload details for Hovod" do
        create_response =
          instance_double(
            Faraday::Response,
            status: 201,
            body: { "data" => { "id" => "hovod-uid-123" } }.to_json,
            headers: {},
          )
        upload_url_response =
          instance_double(
            Faraday::Response,
            status: 200,
            body: { "data" => { "uploadUrl" => "https://s3.example.com/sources/hovod-uid-123/input.mp4" } }.to_json,
            headers: {},
          )

        allow(Faraday).to receive(:post).with(
          "#{api_url}/v1/assets",
          anything,
          hash_including("Authorization" => "Bearer #{api_key}"),
        ).and_return(create_response)

        allow(Faraday).to receive(:post).with(
          "#{api_url}/v1/assets/hovod-uid-123/upload-url",
          nil,
          hash_including("Authorization" => "Bearer #{api_key}"),
        ).and_return(upload_url_response)

        context = described_class.call(params: service_params)

        expect(context.success?).to eq(true)
        expect(context[:upload_details]).to include(
          upload_url: "https://s3.example.com/sources/hovod-uid-123/input.mp4",
          stream_media_id: "hovod-uid-123",
          tus_resumable: "1.0.0",
        )
      end
    end
  end
end
