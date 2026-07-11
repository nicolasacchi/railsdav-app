require "fileutils"

# Writes a consistent snapshot of the primary SQLite database using
# `VACUUM INTO`, which is safe to run against a live (WAL-mode) database, then
# prunes old snapshots. There was previously no backup story at all for the
# SQLite data — this is the in-app baseline (pair with off-host copying of
# storage/backups for real durability).
class BackupDatabaseJob < ApplicationJob
  queue_as :default

  DEFAULT_KEEP = 7

  def perform
    path = primary_database_path
    if path.blank?
      Rails.logger.info("[backup] skipped: primary database is not an on-disk SQLite file")
      return nil
    end

    dir = backup_dir
    FileUtils.mkdir_p(dir)
    timestamp = Time.current.utc.strftime("%Y%m%dT%H%M%SZ")
    dest = dir.join("primary-#{timestamp}.sqlite3")

    connection = ActiveRecord::Base.connection
    connection.execute("VACUUM INTO #{connection.quote(dest.to_s)}")

    prune(dir)
    Rails.logger.info("[backup] wrote #{dest} (#{File.size(dest)} bytes)")
    dest.to_s
  end

  private

  def backup_dir
    Rails.root.join(ENV.fetch("DB_BACKUP_DIR", "storage/backups"))
  end

  def keep
    value = ENV.fetch("DB_BACKUP_KEEP", DEFAULT_KEEP).to_i
    value.positive? ? value : DEFAULT_KEEP
  end

  def primary_database_path
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    return nil unless config[:adapter].to_s.include?("sqlite")
    database = config[:database].to_s
    return nil if database.blank? || database.include?(":memory:")
    database
  end

  def prune(dir)
    snapshots = Dir.glob(dir.join("primary-*.sqlite3")).sort
    excess = snapshots.size - keep
    return unless excess.positive?
    snapshots.first(excess).each { |file| File.delete(file) }
  end
end
