require "rails_helper"

RSpec.describe "Invoices" do
  let(:company) { create(:company) }
  let(:requester) { create(:user, company:) }
  let(:approver) { create(:user, :approver, company:) }

  def rows = Nokogiri::HTML(response.body).css("tbody tr").map { it.css("td").map { |td| td.text.squish } }

  describe "GET /invoices" do
    it "is the root page" do
      sign_in_as(requester)
      get root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<h1", "Invoices")
    end

    it "lists an approver's company non-drafts by due date, with exact money and text status" do
      create(:invoice, :pending, company:, submitted_by: requester, vendor_name: "Later Ltd", due_date: Date.current + 9, total_minor_units: 123_456, currency: "JPY")
      create(:invoice, :approved, company:, submitted_by: requester, vendor_name: "Sooner GmbH", due_date: Date.current + 2, total_minor_units: 123_456, currency: "BHD")
      create(:invoice, company:, submitted_by: requester, vendor_name: "Draft Co")
      create(:invoice, :pending, vendor_name: "Foreign Inc")

      sign_in_as(approver)
      get invoices_path

      expect(rows.map(&:first)).to eq([ "Sooner GmbH", "Later Ltd" ])
      expect(rows.first).to include("BHD 123.456", "Approved (not paid)")
      expect(rows.last).to include("JPY 123,456", "Pending approval")
      expect(response.body).not_to include("Draft Co", "Foreign Inc")
    end

    it "lists a requester's own invoices only, including drafts" do
      create(:invoice, company:, submitted_by: requester, vendor_name: "My Draft")
      create(:invoice, :pending, company:, vendor_name: "Colleague Pending")

      sign_in_as(requester)
      get invoices_path

      expect(rows.map(&:first)).to eq([ "My Draft" ])
    end

    it "filters by status within the visible set" do
      create(:invoice, :pending, company:, submitted_by: requester, vendor_name: "Pending One")
      create(:invoice, :rejected, company:, submitted_by: requester, vendor_name: "Rejected One")
      create(:invoice, :pending, vendor_name: "Foreign Pending")

      sign_in_as(approver)
      get invoices_path(status: "PENDING")

      expect(rows.map(&:first)).to eq([ "Pending One" ])
      expect(Nokogiri::HTML(response.body).at("select#status option[selected]").text).to eq("Pending approval")
    end

    it "ignores an unknown status filter" do
      create(:invoice, :pending, company:, submitted_by: requester, vendor_name: "Pending One")
      sign_in_as(approver)
      get invoices_path(status: "paid")
      expect(rows.map(&:first)).to eq([ "Pending One" ])
    end

    it "shows an explicit empty state" do
      sign_in_as(approver)
      get invoices_path(status: "rejected")
      expect(rows).to eq([ [ "No rejected invoices to show." ] ])

      get invoices_path
      expect(rows.first.first).to start_with("No submitted invoices yet.")
    end

    it "paginates 25 rows per page" do
      create_list(:invoice, 26, :pending, company:, submitted_by: requester) { |inv, i| inv.update!(due_date: Date.current + i, vendor_name: "Vendor #{i.to_s.rjust(2, "0")}") }
      sign_in_as(approver)

      get invoices_path
      expect(rows.size).to eq(25)
      expect(response.body).to include("Next page")
      expect(response.body).not_to include("Previous page")

      get invoices_path(page: 2)
      expect(rows.map(&:first)).to eq([ "Vendor 25" ])
      expect(response.body).to include("Previous page")
      expect(response.body).not_to include("Next page")

      get invoices_path(page: "99999999999999999999")
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /invoices/:uuid" do
    let(:invoice) { create(:invoice, :pending, company:, submitted_by: requester, vendor_name: "Shown Vendor", total_minor_units: 123_456, currency: "USD", due_date: Date.new(2026, 12, 1)) }

    it "shows the invoice at a UUID URL, with no sequential id in the URL or the page" do
      sign_in_as(approver)
      invoice
      get invoices_path
      href = Nokogiri::HTML(response.body).at_xpath("//a[text()='Shown Vendor']")["href"]
      expect(href).to eq("/invoices/#{invoice.uuid}")

      get href
      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML(response.body)
      details = page.css("dt").map(&:text).zip(page.css("dd").map { it.text.squish }).to_h
      expect(details).to eq(
        "Amount" => "USD 1,234.56", "Currency" => "USD", "Due date" => "December 1, 2026",
        "Status" => "Pending approval", "Version" => "1", "Submitted by" => requester.name
      )
      expect(page.css("[href], [action]").map { it["href"] || it["action"] }).to all(satisfy { !it.match?(%r{/\d+(\z|[/?])}) })
      expect(response.body).not_to match(/\binvoice[_-]?id\b|"#{invoice.id}"/)
    end

    it "shows an approval history section with an explicit empty state" do
      sign_in_as(approver)
      get invoice_path(invoice)
      history = Nokogiri::HTML(response.body).at("section[aria-labelledby=history-heading]")
      expect(history.text.squish).to eq("Approval history No history yet.")
    end

    it "labels an approved invoice as not paid and offers no controls on terminal statuses" do
      sign_in_as(approver)
      %i[approved rejected].each do |status|
        terminal = create(:invoice, status, company:, submitted_by: requester)
        get invoice_path(terminal)
        main = Nokogiri::HTML(response.body).at("main")
        expect(main.css("form, button, input, select, textarea")).to be_empty
        expect(main.text).to include("does not pay the invoice")
      end
      expect(response.body).to include("Rejected")

      get invoice_path(create(:invoice, :approved, company:, submitted_by: requester))
      expect(response.body).to include("Approved (not paid)")
    end

    describe "not found" do
      let(:missing_body) do
        sign_in_as(approver)
        get invoice_path(SecureRandom.uuid)
        expect(response).to have_http_status(:not_found)
        response.body
      end

      it "explains in text and links back to the list" do
        page = Nokogiri::HTML(missing_body)
        expect(page.at("h1").text).to eq("Invoice not available")
        expect(page.at_xpath("//main//a[text()='Back to the invoice list']")["href"]).to eq("/invoices")
      end

      it "answers another company's UUID exactly like a missing record" do
        foreign = create(:invoice, :pending, vendor_name: "Secret Foreign Vendor")
        body = missing_body
        get invoice_path(foreign)
        expect(response).to have_http_status(:not_found)
        expect(response.body).to eq(body)
        expect(response.body).not_to include("Secret Foreign Vendor")
      end

      it "answers a sequential id exactly like a missing record" do
        body = missing_body
        get "/invoices/#{invoice.id}"
        expect(response).to have_http_status(:not_found)
        expect(response.body).to eq(body)
      end

      it "hides another requester's invoice and every draft from non-authors" do
        colleague = create(:user, company:)
        draft = create(:invoice, company:, submitted_by: requester)
        pending = create(:invoice, :pending, company:, submitted_by: requester)

        sign_in_as(colleague)
        [ draft, pending ].each do |hidden|
          get invoice_path(hidden)
          expect(response).to have_http_status(:not_found)
        end

        sign_in_as(approver)
        get invoice_path(draft)
        expect(response).to have_http_status(:not_found)

        sign_in_as(requester)
        get invoice_path(draft)
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "live refresh" do
    # The tag carries only a signed name; the verifier is what proves which stream a client may subscribe to.
    def stream_names = Nokogiri::HTML(response.body).css("turbo-cable-stream-source[channel='Turbo::StreamsChannel']")
      .map { Turbo::StreamsChannel.verified_stream_name(it["signed-stream-name"]) }

    def meta(name) = Nokogiri::HTML(response.body).at("head meta[name='#{name}']")&.[]("content")

    it "subscribes the list and detail pages to the viewer's company stream only, with morph refreshes" do
      other = create(:company)
      sign_in_as(approver)

      [ invoices_path, invoice_path(create(:invoice, :pending, company:, submitted_by: requester)) ].each do |path|
        get path
        expect(stream_names).to eq([ "#{company.to_gid_param}:invoices" ])
        expect(stream_names.join).not_to include(other.to_gid_param)
        expect(meta("turbo-refresh-method")).to eq("morph")
        expect(meta("turbo-refresh-scroll")).to eq("preserve")
      end
    end

    it "refuses a stream name the server did not sign" do
      expect(Turbo::StreamsChannel.verified_stream_name("#{create(:company).to_gid_param}:invoices")).to be_nil
    end
  end
end
