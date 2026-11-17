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

  describe ".parse" do
    it "converts exact decimal strings to minor units by the currency's exponent" do
      expect(Money.parse("1,234.56", "USD")).to eq(123_456)
      expect(Money.parse("1234.5", "EUR")).to eq(123_450)
      expect(Money.parse("12", "GBP")).to eq(1_200)
      expect(Money.parse("0.001", "BHD")).to eq(1)
      expect(Money.parse("165,000", "JPY")).to eq(165_000)
      expect(Money.parse(" 0.10 ", "USD")).to eq(10)
      expect(Money.parse("010.09", "USD")).to eq(1_009) # leading zeros are decimal, never octal
    end

    it "accepts the maximum and round-trips what it formats" do
      expect(Money.parse("999,999,999,999.99", "USD")).to eq(99_999_999_999_999)
      [ [ 123_456, "USD" ], [ 7, "BHD" ], [ 4_820_000, "JPY" ] ].each do |units, currency|
        expect(Money.parse(Money.new(units, currency).amount, currency)).to eq(units)
      end
    end

    it "rejects amounts above the maximum" do
      expect(Money.parse("1,000,000,000,000.00", "USD")).to be_nil
      expect(Money.parse("100000000000000", "JPY")).to be_nil
      expect(Money.parse("9" * 40, "USD")).to be_nil
    end

    it "rejects more decimals than the currency allows instead of rounding" do
      expect(Money.parse("10.005", "USD")).to be_nil
      expect(Money.parse("1.5", "JPY")).to be_nil
      expect(Money.parse("0.0001", "BHD")).to be_nil
    end

    it "rejects negatives, non-numerics, misplaced separators and unsupported currencies" do
      [ "-1.00", "", " ", "abc", "1e3", "1.2.3", "12,34", "1,2345", ",100", "1 000", "+5", "0x10", "１２", ".5", nil, [ "1" ] ].each do |input|
        expect(Money.parse(input, "USD")).to be_nil, "expected #{input.inspect} to be rejected"
      end
      expect(Money.parse("1.00", "XTS")).to be_nil
      expect(Money.parse("1.00", nil)).to be_nil
    end
  end
end
