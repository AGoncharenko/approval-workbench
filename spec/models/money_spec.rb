require "rails_helper"

RSpec.describe Money do
  it "formats by the currency's minor-unit exponent" do
    expect(Money.new(123456, "USD").to_s).to eq("USD 1,234.56")
    expect(Money.new(123456, "JPY").to_s).to eq("JPY 123,456")
    expect(Money.new(123456, "BHD").to_s).to eq("BHD 123.456")
  end

  it "formats zero and sub-unit amounts with padding" do
    expect(Money.new(0, "USD").to_s).to eq("USD 0.00")
    expect(Money.new(0, "JPY").to_s).to eq("JPY 0")
    expect(Money.new(5, "EUR").to_s).to eq("EUR 0.05")
    expect(Money.new(7, "BHD").to_s).to eq("BHD 0.007")
  end

  it "formats the largest storable total exactly" do
    expect(Money.new(99_999_999_999_999, "USD").to_s).to eq("USD 999,999,999,999.99")
    expect(Money.new(99_999_999_999_999, "JPY").to_s).to eq("JPY 99,999,999,999,999")
  end

  it "keeps the sign for negative amounts" do
    expect(Money.new(-1050, "USD").to_s).to eq("USD -10.50")
  end

  it "defaults unknown currencies to exponent 2" do
    expect(Money.new(100, "XTS").to_s).to eq("XTS 1.00")
  end

  it "refuses Floats, Decimals and malformed currencies" do
    expect { Money.new(12.34, "USD") }.to raise_error(ArgumentError)
    expect { Money.new(BigDecimal("12"), "USD") }.to raise_error(ArgumentError)
    expect { Money.new(100, "usd") }.to raise_error(ArgumentError)
    expect { Money.new(100, nil) }.to raise_error(ArgumentError)
  end
end
