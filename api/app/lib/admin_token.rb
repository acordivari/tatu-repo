# The shared moderation token (ADMIN_TOKEN). One place decides whether an
# Authorization header carries it, so the controller that gates the candidates
# endpoints and the throttle that counts failed attempts cannot disagree.
module AdminToken
  # True only when a token is configured and the header carries exactly it.
  # With no ADMIN_TOKEN set, nothing is valid: the endpoints are disabled.
  def self.valid?(authorization_header)
    expected = ENV["ADMIN_TOKEN"].to_s
    provided = authorization_header.to_s.delete_prefix("Bearer ").strip
    expected.present? && provided.present? &&
      ActiveSupport::SecurityUtils.secure_compare(provided, expected)
  end
end
