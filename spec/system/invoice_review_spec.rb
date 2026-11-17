require "rails_helper"

RSpec.describe "Invoice review by keyboard", type: :system do
  let(:company) { create(:company, name: "Keyboard Co") }
  let(:requester) { create(:user, company:, email_address: "keys@example.com") }

  before do
    create(:invoice, company:, submitted_by: requester, vendor_name: "Draft Vendor", due_date: Date.current + 3)
    create(:invoice, :pending, company:, submitted_by: requester, vendor_name: "Pending Vendor", due_date: Date.current + 5,
      total_minor_units: 123_456, currency: "JPY")
  end

  def focused = page.evaluate_script("document.activeElement")
  def tab_until(max: 25) = max.times { focused.send_keys(:tab) && (return focused if yield(focused)) }.then { raise "focus never reached target" }

  it "operates the list, a filter and the detail page with the keyboard, marking the form busy while it submits" do
    visit root_path
    fill_in "Email address", with: "keys@example.com"
    fill_in "Password", with: "test-password-123"
    click_on "Sign in"
    expect(page).to have_css("h1", text: "Invoices")

    page.find("body").send_keys(:tab)
    expect(focused.text).to eq("Skip to main content")
    expect(page.evaluate_script("getComputedStyle(document.activeElement).outlineStyle")).to eq("solid")

    # Record the form's state at Turbo's submit-start, when the request is in flight.
    page.execute_script(<<~JS)
      document.addEventListener("turbo:submit-start", (e) => {
        window.busySeen = e.target.getAttribute("aria-busy")
        window.submitLabel = e.target.querySelector("button").textContent
      }, { once: true })
    JS

    select_box = tab_until { it.tag_name == "select" }
    expect(select_box[:id]).to eq("status")
    select_box.send_keys("Pending")
    filter = tab_until { it.tag_name == "button" }
    expect(filter.text).to eq("Filter")
    filter.send_keys(:enter)

    expect(page).to have_current_path(/status=pending/)
    expect(page).to have_css("tbody tr", count: 1)
    expect(page.evaluate_script("window.busySeen")).to eq("true")
    expect(page.evaluate_script("window.submitLabel")).to eq("Filtering…")
    expect(page).to have_no_css("form[aria-busy]")

    link = tab_until { it.tag_name == "a" && it.text == "Pending Vendor" }
    link.send_keys(:enter)

    expect(page).to have_css("h1", text: "Pending Vendor")
    expect(page).to have_text("JPY 123,456")
    expect(page).to have_text("Pending approval")
    expect(page).to have_css("section h2", text: "Approval history")
    expect(page).to have_text("No history yet.")
    expect(tab_until { it.text == "Back to invoices" }).to be_present
  end

  it "shows a styled 404 with a way back to the list" do
    visit root_path
    fill_in "Email address", with: "keys@example.com"
    fill_in "Password", with: "test-password-123"
    click_on "Sign in"
    expect(page).to have_css("h1", text: "Invoices")
    visit invoice_path(SecureRandom.uuid)

    expect(page).to have_css("h1", text: "Invoice not available")
    click_on "Back to the invoice list"
    expect(page).to have_css("h1", text: "Invoices")
  end
end
