# Integer minor units plus an ISO-4217 code. Formatting is pure integer arithmetic; Floats are refused.
class Money < Data.define(:minor_units, :currency)
  # shortcut: only the exponents the demo needs; unknown codes default to 2. Use a full ISO table if more currencies arrive.
  EXPONENTS = { "JPY" => 0, "KRW" => 0, "BHD" => 3, "KWD" => 3 }.freeze

  def initialize(minor_units:, currency:)
    raise ArgumentError, "minor_units must be an Integer, got #{minor_units.class}" unless minor_units.is_a?(Integer)
    raise ArgumentError, "currency must be three uppercase letters" unless currency.to_s.match?(/\A[A-Z]{3}\z/)
    super
  end

  def exponent = EXPONENTS.fetch(currency, 2)

  def to_s
    units, fraction = minor_units.abs.divmod(10**exponent)
    amount = units.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
    amount += ".#{fraction.to_s.rjust(exponent, "0")}" if exponent.positive?
    "#{currency} #{"-" if minor_units.negative?}#{amount}"
  end
end
