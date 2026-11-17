# Be sure to restart your server when you modify this file.

# Content security policy: only this origin may supply scripts, styles, images, fonts and connections (including the
# Action Cable websocket). Importmap, Turbo's progress bar and other inline tags carry the per-session nonce.
# See https://guides.rubyonrails.org/security.html#content-security-policy-header
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src :self
    policy.style_src :self
    policy.img_src :self, :data
    policy.font_src :self, :data
    policy.connect_src :self
    policy.object_src :none
    policy.base_uri :self
    policy.form_action :self
    policy.frame_ancestors :none
  end

  # A fresh random nonce per response. (The session id, Rails' commented default, is empty before a visitor's first
  # session write, which would block the importmap on the sign-in page.) Turbo keeps the first page's policy and
  # this app puts no inline scripts in page bodies, so a nonce that changes between visits is safe.
  config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end
