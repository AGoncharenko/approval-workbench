require "rails_helper"

# Each shared partial carries an accessibility rule; these specs pin that rule down.
RSpec.describe "shared partials", type: :view do
  def html = Nokogiri::HTML.fragment(rendered)

  describe "_status_badge" do
    it "renders a text label for every status" do
      labels = Invoice.statuses.keys.map { render(partial: "shared/status_badge", locals: { status: it }).then { Nokogiri::HTML.fragment(it).text.strip } }
      expect(labels).to eq([ "Draft", "Pending approval", "Approved (not paid)", "Rejected" ])
    end
  end

  describe "_money" do
    it "always shows the currency code with integer-derived digits" do
      render partial: "shared/money", locals: { amount: Money.new(123_456, "JPY") }
      expect(html.text.strip).to eq("JPY 123,456")
      expect(html.at("span")["class"]).to include("tabular-nums", "text-right")
    end

    it "renders an invoice's total" do
      render partial: "shared/money", locals: { amount: build(:invoice, total_minor_units: 5, currency: "EUR").total }
      expect(html.text.strip).to eq("EUR 0.05")
    end

    it "refuses anything that is not a Money, such as a Float or an Invoice" do
      [ 12.5, build(:invoice) ].each do |amount|
        expect { render partial: "shared/money", locals: { amount: } }.to raise_error(ActionView::Template::Error, /expects a Money/)
      end
    end
  end

  describe "_notice" do
    it "is a polite status live region, present even when empty" do
      render partial: "shared/notice", locals: { message: nil }
      expect(html.at("#notice[role=status][aria-live=polite]")).to be_present
      expect(html.text.strip).to be_empty
    end

    it "shows the message" do
      render partial: "shared/notice", locals: { message: "Invoice changed since you opened it.", variant: :conflict }
      expect(html.at("[role=status]").text).to include("Invoice changed since you opened it.")
    end
  end

  describe "_button" do
    it "sets a submitting label and keeps extra data attributes" do
      render partial: "shared/button", locals: { label: "Approve", submits_with: "Approving…", data: { action: "x#y" } }
      button = html.at("button[type=submit]")
      expect(button.text).to eq("Approve")
      expect(button["data-turbo-submits-with"]).to eq("Approving…")
      expect(button["data-action"]).to eq("x#y")
      expect(button["disabled"]).to be_nil
    end

    it "can be disabled" do
      render partial: "shared/button", locals: { label: "Approve", disabled: true }
      expect(html.at("button")["disabled"]).to be_present
    end
  end

  describe "_data_table" do
    let(:columns) { [ { label: "Vendor" }, { label: "Amount", numeric: true } ] }

    it "has a caption and column-scoped headers, yielding each row" do
      render(layout: "shared/data_table", locals: { caption: "Invoices", columns:, rows: %w[Acme Globex], empty_message: "None" }) { |row| "<td>#{row}</td>".html_safe }
      expect(html.at("table caption").text).to eq("Invoices")
      expect(html.css("th[scope=col]").map(&:text)).to eq(%w[Vendor Amount])
      expect(html.css("tbody td").map(&:text)).to eq(%w[Acme Globex])
      expect(html.at("[role=region][tabindex='0']")["aria-labelledby"]).to eq(html.at("caption")["id"])
    end

    it "renders an empty-state row spanning all columns" do
      render(layout: "shared/data_table", locals: { caption: "Invoices", columns:, rows: [], empty_message: "No invoices match." }) { "" }
      cell = html.at("tbody tr td")
      expect(cell.text).to eq("No invoices match.")
      expect(cell["colspan"]).to eq("2")
    end
  end

  describe "_form_field" do
    def field(error: nil)
      view.form_with(url: "/x", scope: :invoice) do |form|
        view.render "shared/form_field", form:, attribute: :vendor_name, label: "Vendor", error:
      end
    end

    it "links an error to its input and marks it invalid" do
      fragment = Nokogiri::HTML.fragment(field(error: "can't be blank"))
      input = fragment.at("input[name='invoice[vendor_name]']")
      error = fragment.at("##{input['aria-describedby']}")
      expect(error.text).to eq("can't be blank")
      expect(input["aria-invalid"]).to eq("true")
      expect(fragment.at("label[for='#{input['id']}']").text).to eq("Vendor")
    end

    it "has no error wiring when valid" do
      input = Nokogiri::HTML.fragment(field).at("input[name='invoice[vendor_name]']")
      expect(input["aria-describedby"]).to be_nil
      expect(input["aria-invalid"]).to eq("false")
    end
  end
end
