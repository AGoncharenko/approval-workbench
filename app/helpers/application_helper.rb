module ApplicationHelper
  # Machine-readable date plus a localized label, e.g. <time datetime="2026-12-01">December 1, 2026</time>.
  def date_tag(date, format: :long) = tag.time(l(date, format:), datetime: date.iso8601)
end
