namespace :invitations do
  desc 'Generate a single-use signup link. Set BASE_URL env var for the deployed host.'
  task generate: :environment do
    inv  = Invitation.create!
    base = ENV.fetch('BASE_URL', 'http://localhost:5173')
    puts "#{base}/signup?token=#{inv.token}"
  end
end
