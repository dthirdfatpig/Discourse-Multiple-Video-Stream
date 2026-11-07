# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseMultipleVideoStream::PrepareUploadService do
  let(:service_params) do
    {
      file_name: "test-clip.mp4",
      file_size: "10485760",
      file_type: "video/mp4",
      creator_id: 1,
    }
  end

  context "when provider is Cloudflare" do
    before do
      SiteSetting.multiple_video_stream_provider = "Cloudflare"
      SiteSetting.multiple_video_stream_account_id = "cf-acc-123"
      SiteSetting.multiple_video_stream_api_token = "cf-token"
    end

    it "returns cloudflare upload endpoint" do
      context = described_class.call(params: service_params)

      expect(context.success?).to eq(true)
      expect(context[:upload_details]).to eq(
        provider: "cloudflare",
        endpoint: "/multiple-video-stream/upload-url.json",
      )
    end

    it "fails when credentials are missing" do
      SiteSetting.multiple_video_stream_api_token = ""

      context = described_class.call(params: service_params)

      expect(context.failure?).to eq(true)
      expect(context[:error]).to eq(I18n.t("multiple_video_stream.errors.misconfigured"))
      expect(context[:status]).to eq(422)
    end
  end

  context "when provider is Bunny" do
    let(:library_id) { "99999" }
    let(:api_key) { "bunny-secret-api-key" }

    before do
      SiteSetting.multiple_video_stream_provider = "Bunny"
      SiteSetting.multiple_video_stream_bunny_library_id = library_id
      SiteSetting.multiple_video_stream_bunny_api_key = api_key
    end

    it "creates video on Bunny and returns client TUS credentials" do
      create_response =
        instance_double(
          Faraday::Response,
          status: 200,
          body: { "guid" => "bunny-video-uuid" }.to_json,
          headers: {},
        )

      allow(Faraday).to receive(:post).with(
        "https://video.bunnycdn.com/library/#{library_id}/videos",
        anything,
        hash_including("AccessKey" => api_key),
      ).and_return(create_response)

      context = described_class.call(params: service_params)

      expect(context.success?).to eq(true)
      expect(context[:upload_details][:provider]).to eq("bunny")
      expect(context[:upload_details][:endpoint]).to eq("https://video.bunnycdn.com/tusupload")
      expect(context[:upload_details][:video_id]).to eq("bunny-video-uuid")
      expect(context[:upload_details][:headers]).to include(
        "LibraryId" => library_id,
        "VideoId" => "bunny-video-uuid",
      )
      expect(context[:upload_details][:headers]["AuthorizationSignature"]).to be_present
      expect(context[:upload_details][:headers]["AuthorizationExpire"]).to be_present
    end

    it "uses original file name when keep_original_name is enabled" do
      SiteSetting.multiple_video_stream_keep_original_name = true

      create_response =
        instance_double(
          Faraday::Response,
          status: 200,
          body: { "guid" => "bunny-video-uuid" }.to_json,
          headers: {},
        )

      allow(Faraday).to receive(:post).with(
        "https://video.bunnycdn.com/library/#{library_id}/videos",
        { title: "test-clip.mp4" }.to_json,
        anything,
      ).and_return(create_response)

      context = described_class.call(params: service_params)

      expect(context.success?).to eq(true)
      expect(Faraday).to have_received(:post).with(
        "https://video.bunnycdn.com/library/#{library_id}/videos",
        { title: "test-clip.mp4" }.to_json,
        anything,
      )
    end

    it "fails when Bunny credentials are missing" do
      SiteSetting.multiple_video_stream_bunny_library_id = ""

      context = described_class.call(params: service_params)

      expect(context.failure?).to eq(true)
      expect(context[:error]).to eq(I18n.t("multiple_video_stream.errors.misconfigured"))
      expect(context[:status]).to eq(422)
    end

    it "fails when Bunny video creation fails" do
      create_response =
        instance_double(
          Faraday::Response,
          status: 401,
          body: { "message" => "Unauthorized" }.to_json,
          headers: {},
        )

      allow(Faraday).to receive(:post).and_return(create_response)

      context = described_class.call(params: service_params)

      expect(context.failure?).to eq(true)
      expect(context[:error]).to eq(I18n.t("multiple_video_stream.errors.upload_url"))
      expect(context[:status]).to eq(422)
    end
  end

  context "when provider is Hovod" do
    let(:api_url) { "https://hovod.example.com" }
    let(:api_key) { "mk_test_api_key_12345" }

    before do
      SiteSetting.multiple_video_stream_provider = "Hovod"
      SiteSetting.multiple_video_stream_hovod_api_url = api_url
      SiteSetting.multiple_video_stream_hovod_api_key = api_key
    end

    it "creates asset and returns presigned upload URL details" do
      create_asset_response =
        instance_double(
          Faraday::Response,
          status: 201,
          body: { "data" => { "id" => "hovodAsset12", "playbackId" => "hovodPlay16chars", "status" => "created" } }.to_json,
          headers: {},
        )

      upload_url_response =
        instance_double(
          Faraday::Response,
          status: 200,
          body: { "data" => { "uploadUrl" => "https://s3.example.com/sources/hovodAsset12/input.mp4?sig=abc", "method" => "PUT" } }.to_json,
          headers: {},
        )

      allow(Faraday).to receive(:post).with(
        "#{api_url}/v1/assets",
        anything,
        hash_including("Authorization" => "Bearer #{api_key}"),
      ).and_return(create_asset_response)

      allow(Faraday).to receive(:post).with(
        "#{api_url}/v1/assets/hovodAsset12/upload-url",
        nil,
        hash_including("Authorization" => "Bearer #{api_key}"),
      ).and_return(upload_url_response)

      context = described_class.call(params: service_params)

      expect(context.success?).to eq(true)
      expect(context[:upload_details][:provider]).to eq("hovod")
      expect(context[:upload_details][:video_id]).to eq("hovodAsset12")
      expect(context[:upload_details][:playback_id]).to eq("hovodPlay16chars")
      expect(context[:upload_details][:upload_url]).to include("https://s3.example.com/sources/hovodAsset12/input.mp4")
      expect(context[:upload_details][:upload_method]).to eq("PUT")
    end

    it "fails when Hovod credentials are missing" do
      SiteSetting.multiple_video_stream_hovod_api_key = ""

      context = described_class.call(params: service_params)

      expect(context.failure?).to eq(true)
      expect(context[:error]).to eq(I18n.t("multiple_video_stream.errors.misconfigured"))
      expect(context[:status]).to eq(422)
    end

    it "fails when Hovod asset creation fails" do
      error_response =
        instance_double(
          Faraday::Response,
          status: 401,
          body: { "error" => "Unauthorized" }.to_json,
          headers: {},
        )

      allow(Faraday).to receive(:post).and_return(error_response)

      context = described_class.call(params: service_params)

      expect(context.failure?).to eq(true)
      expect(context[:error]).to eq(I18n.t("multiple_video_stream.errors.upload_url"))
      expect(context[:status]).to eq(422)
    end
  end
end
