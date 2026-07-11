require "rails_helper"

# Regression coverage for CSV formula-injection neutralization in exports.
RSpec.describe Contacts::Exporter, ".to_csv formula injection" do
  let(:addressbook) { create(:addressbook) }

  def contact_with_note(note)
    vcard = Vcard::Parser.generate(full_name: "Victim", note: note)
    create(:contact, addressbook: addressbook, uri: "#{SecureRandom.uuid}.vcf", vcard_data: vcard)
  end

  it "prefixes a formula-leading note cell with a quote" do
    contact = contact_with_note("=HYPERLINK(\"http://evil\",\"x\")")
    csv = described_class.to_csv([contact])
    # The dangerous cell is rendered as literal text (leading apostrophe), so it
    # is not evaluated as a formula by spreadsheet apps.
    expect(csv).to include("'=HYPERLINK")
    expect(csv).not_to match(/(^|,)=HYPERLINK/)
  end

  it "neutralizes +, -, and @ formula prefixes" do
    ["+1+1", "-2-2", "@SUM(A1)"].each do |payload|
      contact = contact_with_note(payload)
      csv = described_class.to_csv([contact])
      expect(csv).to include("'#{payload}")
    end
  end

  it "leaves ordinary values untouched" do
    contact = contact_with_note("Just a normal note")
    csv = described_class.to_csv([contact])
    expect(csv).to include("Just a normal note")
    expect(csv).not_to include("'Just a normal note")
  end
end
