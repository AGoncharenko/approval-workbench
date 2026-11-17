# Integer minor units plus an ISO-4217 code. Formatting is pure integer arithmetic; Floats are refused.
class Money < Data.define(:minor_units, :currency)
  # The closed list of currencies invoices may use, with their minor-unit exponents.
  EXPONENTS = { "USD" => 2, "EUR" => 2, "GBP" => 2, "JPY" => 0, "BHD" => 3 }.freeze
  CURRENCIES = EXPONENTS.keys.freeze
  MAX_MINOR_UNITS = 99_999_999_999_999 # matches the invoices_total_range CHECK

  # Exact decimal string -> Integer minor units, or nil when the input isn't a valid amount for the currency.
  # Integer-only: no Float, no BigDecimal, no rounding. Commas are accepted only as thousands separators.
  def self.parse(input, currency)
    exponent = EXPONENTS[currency] or return nil
    text = input.to_s.strip
    return nil if text.length > 40

    match = text.match(/\A(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{0,#{exponent}}))?\z/) or return nil
    minor_units = Integer(match[1].delete(",") + match[2].to_s.ljust(exponent, "0"), 10) # base 10: "010" is not octal
    minor_units if minor_units <= MAX_MINOR_UNITS
  end

  def initialize(minor_units:, currency:)
    raise ArgumentError, "minor_units must be an Integer, got #{minor_units.class}" unless minor_units.is_a?(Integer)
    raise ArgumentError, "currency must be three uppercase letters" unless currency.to_s.match?(/\A[A-Z]{3}\z/)
    super
  end

  def exponent = EXPONENTS.fetch(currency, 2)

  # The amount without the currency code, e.g. "1,234.56"; Money.parse reads it back exactly.
  def amount
    units, fraction = minor_units.abs.divmod(10**exponent)
    text = units.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
    text += ".#{fraction.to_s.rjust(exponent, "0")}" if exponent.positive?
    "#{"-" if minor_units.negative?}#{text}"
  end

  def to_s = "#{currency} #{amount}"
end
