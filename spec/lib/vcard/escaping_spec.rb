require "rails_helper"

# Regression coverage for vCard TEXT escaping: user input must not be able to
# inject new vCard lines/properties, and special characters must round-trip.
RSpec.describe "Vcard::Parser escaping" do
  it "neutralizes embedded CR/LF so extra properties cannot be injected" do
    vcard = Vcard::Parser.generate(full_name: "Alice", note: "hi\r\nEMAIL:attacker@evil.com")

    lines = vcard.split("\r\n")
    # The injected EMAIL must not become its own property line.
    expect(lines).not_to include("EMAIL:attacker@evil.com")
    expect(vcard).to include('NOTE:hi\nEMAIL:attacker@evil.com')
  end

  it "prevents splicing a second phantom vCard via END/BEGIN injection" do
    payload = "x\r\nEND:VCARD\r\nBEGIN:VCARD\r\nFN:Fake Support\r\nTEL:+1900\r\nEND:VCARD"
    vcard = Vcard::Parser.generate(full_name: "Alice", note: payload)

    # The injected newlines are escaped, so the payload stays inside one NOTE
    # line: exactly one physical BEGIN/END delimiter remains.
    physical_lines = vcard.split("\r\n")
    expect(physical_lines.count { |l| l == "BEGIN:VCARD" }).to eq(1)
    expect(physical_lines.count { |l| l == "END:VCARD" }).to eq(1)
  end

  it "round-trips commas and semicolons in a note" do
    original = "Smith, John; the third"
    vcard = Vcard::Parser.generate(full_name: "Alice", note: original)
    parsed = Vcard::Parser.parse(vcard)
    expect(parsed.note).to eq(original)
  end

  it "round-trips a multi-line note back to real newlines" do
    original = "line one\nline two"
    vcard = Vcard::Parser.generate(full_name: "Alice", note: original)
    parsed = Vcard::Parser.parse(vcard)
    expect(parsed.note).to eq(original)
  end

  it "round-trips structured name components containing a semicolon" do
    vcard = Vcard::Parser.generate(first_name: "Jo;hn", last_name: "Doe", full_name: "Jo;hn Doe")
    parsed = Vcard::Parser.parse(vcard)
    expect(parsed.first_name).to eq("Jo;hn")
    expect(parsed.last_name).to eq("Doe")
  end
end
