require "rails_helper"

RSpec.describe CallscreenWebhookJob, type: :job do
  let(:payload) { { "event" => "updated", "username" => "alice", "contact_id" => 1, "phones" => ["+393331234567"] } }

  after { ENV.delete("CALLSCREEN_WEBHOOK_URL") }

  it "is a no-op when no webhook URL is configured" do
    ENV.delete("CALLSCREEN_WEBHOOK_URL")
    expect(Net::HTTP).not_to receive(:new)
    expect(described_class.new.perform(payload)).to be_nil
  end

  it "POSTs the payload as JSON to the configured URL" do
    ENV["CALLSCREEN_WEBHOOK_URL"] = "https://callscreen.example/webhook"

    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)

    captured = nil
    response = Net::HTTPSuccess.allocate
    allow(http).to receive(:request) do |req|
      captured = req
      response
    end

    described_class.new.perform(payload)

    expect(captured.body).to eq(payload.to_json)
    expect(captured["Content-Type"]).to eq("application/json")
  end

  it "raises on a non-success response so ActiveJob retries" do
    ENV["CALLSCREEN_WEBHOOK_URL"] = "https://callscreen.example/webhook"
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:request).and_return(Net::HTTPServerError.allocate.tap { |r| r.instance_variable_set(:@code, "500") })

    expect { described_class.new.perform(payload) }.to raise_error(/callscreen webhook returned/)
  end
end
