if ENV["ADMIN_EMAIL"].present? && ENV["ADMIN_PASSWORD"].present?
  admin = User.find_or_initialize_by(email: ENV["ADMIN_EMAIL"])
  admin.assign_attributes(
    password: ENV["ADMIN_PASSWORD"],
    password_confirmation: ENV["ADMIN_PASSWORD"]
  )
  admin.save!
  admin.update!(admin: true)
  puts "Admin user created: #{admin.email} (#{admin.username})"
end
