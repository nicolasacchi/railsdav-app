namespace :groups do
  desc "Backfill contact groups from existing vCard CATEGORIES and KIND:group data"
  task backfill: :environment do
    Contact.find_each do |contact|
      contact.send(:sync_groups_from_vcard)
    rescue => e
      puts "Error processing contact #{contact.id}: #{e.message}"
    end
    puts "Done backfilling groups."
  end
end
