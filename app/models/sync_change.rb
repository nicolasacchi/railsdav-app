class SyncChange < ApplicationRecord
  belongs_to :addressbook

  validates :uri, presence: true
  validates :sync_token, presence: true, numericality: { only_integer: true }
  validates :change_type, presence: true, inclusion: { in: %w[created modified deleted] }

  scope :since_token, ->(token) { where("sync_token > ?", token) }
end
