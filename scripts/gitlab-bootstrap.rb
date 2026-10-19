# Executed with `gitlab-rails runner` on the GitLab VM.
# Creates (idempotently) a root personal access token with the
# `create_runner` scope, so the runner VM can register itself.
token_value = ENV.fetch('GITLAB_AUTOMATION_TOKEN')
token_name  = 'terraform-runner-bootstrap'

root = User.find_by_username!('root')

unless PersonalAccessToken.find_by_token(token_value)
  token = root.personal_access_tokens.create!(
    name: token_name,
    scopes: %w[create_runner],
    expires_at: 365.days.from_now
  ) { |t| t.set_token(token_value) }
  token.save!
  puts "Created personal access token '#{token_name}'"
end

# Self-hosted instance: disable public sign-ups.
Gitlab::CurrentSettings.update!(signup_enabled: false)
