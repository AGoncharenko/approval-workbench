module ApplicationHelper
  FLASH_VARIANTS = { "alert" => :error, "conflict" => :conflict, "info" => :info, "notice" => :success }.freeze

  # Locals for the page's live region: the first flash kind that is set, styled by that kind.
  def flash_notice
    kind = FLASH_VARIANTS.keys.find { flash[it].present? }
    { message: kind && flash[kind], variant: FLASH_VARIANTS.fetch(kind, :info) }
  end

  # Machine-readable date (or time) plus a localized label, e.g. <time datetime="2026-12-01">December 1, 2026</time>.
  def date_tag(date, format: :long) = tag.time(l(date, format:), datetime: date.iso8601)
end
