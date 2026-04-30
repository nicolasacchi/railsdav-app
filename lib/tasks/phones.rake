namespace :phones do
  desc "Backfill ContactPhoneNumber rows from existing vCard TEL data (skips encrypted contacts)"
  task backfill: :environment do
    total = 0
    failed = 0
    Contact.unencrypted.non_bootstrap.find_each do |contact|
      contact.send(:sync_phone_numbers)
      total += 1
    rescue => e
      failed += 1
      puts "Error processing contact #{contact.id}: #{e.message}"
    end
    puts "Backfilled phone numbers for #{total} contacts (#{failed} failed)."
  end
end
