# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseMultipleVideoStream::VideoStreamController do
  fab!(:user)

  before do
    SiteSetting.multiple_video_stream_enabled = true
    SiteSetting.multiple_video_stream_account_id = "abc123"
    SiteSetting.multiple_video_stream_api_token = "token"
  end

  describe "POST /multiple-video-stream/upload-url" do
    it "requires login" do
      post "/multiple-video-stream/upload-url.json"

      expect(response.status).to eq(403)
    end

    it "returns 404 when the feature is disabled" do
      SiteSetting.multiple_video_stream_enabled = false

      sign_in(user)
      post "/multiple-video-stream/upload-url.json"

      expect(response.status).to eq(404)
    end

    it "returns upload headers when the service succeeds" do
      context =
        Service::Base::Context.new(
          upload_details: {
            upload_url: "https://example.com",
            stream_media_id: "123",
            tus_resumable: "1.0.0",
          },
        )
      allow(DiscourseMultipleVideoStream::VideoUploadService).to receive(:call).and_return(context)

      sign_in(user)
      post "/multiple-video-stream/upload-url.json",
           headers: {
             "Upload-Length" => "1024",
             "Upload-Metadata" => "name ZmlsZS5tcDQ=",
             "Tus-Resumable" => "1.0.0",
           }

      expect(response.status).to eq(201)
      expect(response.headers["Location"]).to eq("https://example.com")
      expect(response.headers["stream-media-id"]).to eq("123")
      expect(DiscourseMultipleVideoStream::VideoUploadService).to have_received(:call).with(
        satisfy do |args|
          expect(args[:params]).to include(
            upload_length: "1024",
            upload_metadata: "name ZmlsZS5tcDQ=",
            tus_resumable: "1.0.0",
            creator_id: user.id,
          )
          true
        end,
      )
    end

    it "renders an error payload when the service fails" do
      failure_context = Service::Base::Context.new
      failure_context.fail(error: "nope", status: 422)
      allow(DiscourseMultipleVideoStream::VideoUploadService).to receive(:call).and_return(failure_context)

      sign_in(user)
      post "/multiple-video-stream/upload-url.json"

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to eq("nope")
      expect(DiscourseMultipleVideoStream::VideoUploadService).to have_received(:call)
    end
  end

  describe "POST /multiple-video-stream/prepare-upload" do
    it "requires login" do
      post "/multiple-video-stream/prepare-upload.json"

      expect(response.status).to eq(403)
    end

    it "returns 404 when the feature is disabled" do
      SiteSetting.multiple_video_stream_enabled = false

      sign_in(user)
      post "/multiple-video-stream/prepare-upload.json"

      expect(response.status).to eq(404)
    end

    it "returns upload details when PrepareUploadService succeeds" do
      context =
        Service::Base::Context.new(
          upload_details: {
            provider: "hovod",
            upload_url: "https://s3.example.com/sources/hovod123/input.mp4",
            video_id: "hovod123",
            upload_method: "PUT",
          },
        )
      allow(DiscourseMultipleVideoStream::PrepareUploadService).to receive(:call).and_return(context)

      sign_in(user)
      post "/multiple-video-stream/prepare-upload.json",
           params: {
             file_name: "sample.mp4",
             file_size: 1024,
             file_type: "video/mp4",
           }

      expect(response.status).to eq(200)
      expect(response.parsed_body["provider"]).to eq("hovod")
      expect(response.parsed_body["video_id"]).to eq("hovod123")
      expect(DiscourseMultipleVideoStream::PrepareUploadService).to have_received(:call).with(
        satisfy do |args|
          expect(args[:params]).to include(
            file_name: "sample.mp4",
            file_size: "1024",
            file_type: "video/mp4",
            creator_id: user.id,
          )
          true
        end,
      )
    end

    it "renders error payload when PrepareUploadService fails" do
      failure_context = Service::Base::Context.new
      failure_context.fail(error: "cannot prepare", status: 422)
      allow(DiscourseMultipleVideoStream::PrepareUploadService).to receive(:call).and_return(failure_context)

      sign_in(user)
      post "/multiple-video-stream/prepare-upload.json"

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to eq("cannot prepare")
    end
  end

  describe "POST /multiple-video-stream/complete-upload" do
    it "requires login" do
      post "/multiple-video-stream/complete-upload.json", params: { video_id: "hovod123" }

      expect(response.status).to eq(403)
    end

    it "calls CompleteUploadService and returns result" do
      context = Service::Base::Context.new(result: { success: true, video_id: "hovod123" })
      allow(DiscourseMultipleVideoStream::CompleteUploadService).to receive(:call).and_return(context)

      sign_in(user)
      post "/multiple-video-stream/complete-upload.json", params: { video_id: "hovod123" }

      expect(response.status).to eq(200)
      expect(response.parsed_body["success"]).to eq(true)
      expect(response.parsed_body["video_id"]).to eq("hovod123")
    end
  end
end
