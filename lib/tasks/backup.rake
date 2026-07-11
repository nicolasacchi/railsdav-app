namespace :db do
  desc "Write a consistent SQLite snapshot of the primary DB to storage/backups (prunes old ones)"
  task backup: :environment do
    path = BackupDatabaseJob.new.perform
    if path
      puts "Backup written: #{path}"
    else
      puts "Backup skipped (primary database is not an on-disk SQLite file)."
    end
  end
end
