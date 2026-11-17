require "rails_helper"

# WCAG 2.x contrast of each token pair in app/assets/tailwind/application.css. Computed ratios:
#   draft    #334155 on #f1f5f9  9.45:1
#   pending  #92400e on #fef3c7  6.37:1
#   approved #166534 on #dcfce7  6.49:1
#   rejected #991b1b on #fee2e2  6.80:1
#   info     #1e3a8a on #dbeafe  8.49:1
#   brand button: white on #1d4ed8 6.70:1; focus ring #b45309 on white 5.02:1 (non-text needs 3:1)
RSpec.describe "theme tokens" do
  let(:tokens) { Rails.root.join("app/assets/tailwind/application.css").read.scan(/--color-([\w-]+):\s*(#\h{6});/).to_h }

  def luminance(hex)
    hex.delete("#").scan(/../).map { it.to_i(16) / 255.0 }
      .map { it <= 0.04045 ? it / 12.92 : ((it + 0.055) / 1.055)**2.4 }
      .zip([ 0.2126, 0.7152, 0.0722 ]).sum { |c, w| c * w }
  end

  def contrast(a, b) = [ luminance(a), luminance(b) ].sort.reverse.then { |hi, lo| ((hi + 0.05) / (lo + 0.05)).round(2) }

  it "gives every status and notice pair at least 4.5:1" do
    ratios = %w[draft pending approved rejected info].to_h { [ it, contrast(tokens["#{it}-fg"], tokens["#{it}-bg"]) ] }
    expect(ratios).to eq("draft" => 9.45, "pending" => 6.37, "approved" => 6.49, "rejected" => 6.8, "info" => 8.49)
    expect(ratios.values).to all(be >= 4.5)
  end

  it "keeps button text and the focus ring readable on white" do
    expect(contrast(tokens["brand"], "#ffffff")).to be >= 4.5
    expect(contrast(tokens["brand-strong"], "#ffffff")).to be >= 4.5
    expect(contrast(tokens["rejected-fg"], "#ffffff")).to be >= 4.5
    expect(contrast(tokens["focus"], "#ffffff")).to be >= 3
  end
end
