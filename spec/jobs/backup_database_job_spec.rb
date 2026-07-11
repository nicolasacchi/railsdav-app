require "rails_helper"

RSpec.describe BackupDatabaseJob, type: :job do
  # SQLite refuses to VACUUM inside a transaction, so this spec can't use the
  # default transactional fixtures. It creates no AR records, so there's nothing
  # to roll back.
  self.use_transactional_tests = false

  let(:backup_dir) { Rails.root.join("tmp", "backups_test_#{SecureRandom.hex(4)}") }

  before { ENV["DB_BACKUP_DIR"] = backup_dir.to_s }

  after do
    ENV.delete("DB_BACKUP_DIR")
    ENV.delete("DB_BACKUP_KEEP")
    FileUtils.rm_rf(backup_dir)
  end

  it "writes a snapshot of the SQLite database" do
    path = described_class.new.perform

    expect(path).to be_present
    expect(File).to exist(path)
    expect(File.size(path)).to be > 0
    # The snapshot is itself a valid SQLite database (magic header).
    expect(File.binread(path, 16)).to start_with("SQLite format 3")
  end

  it "prunes old snapshots beyond the retention limit" do
    ENV["DB_BACKUP_KEEP"] = "2"
    FileUtils.mkdir_p(backup_dir)
    # Seed three stale snapshots with earlier-sorting names.
    ["primary-20200101T000000Z.sqlite3",
     "primary-20200102T000000Z.sqlite3",
     "primary-20200103T000000Z.sqlite3"].each do |name|
      File.write(backup_dir.join(name), "old")
    end

    described_class.new.perform

    remaining = Dir.glob(backup_dir.join("primary-*.sqlite3")).map { |f| File.basename(f) }
    expect(remaining.size).to eq(2)
    # The freshest (just-written) snapshot must survive; the oldest seeds are pruned.
    expect(remaining).not_to include("primary-20200101T000000Z.sqlite3")
  end
end
