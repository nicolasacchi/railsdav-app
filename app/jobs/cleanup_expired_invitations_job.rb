class CleanupExpiredInvitationsJob < ApplicationJob
  def perform
    AddressbookShare.pending
                    .where("invitation_expires_at < ?", Time.current)
                    .destroy_all
  end
end
