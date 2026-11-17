require "rails_helper"

RSpec.describe InvoicePolicy::Scope do
  let(:company) { create(:company) }
  let(:requester) { create(:user, company:) }
  let(:other_requester) { create(:user, company:) }
  let(:approver) { create(:user, :approver, company:) }
  let(:admin) { create(:user, :admin, company:) }

  let!(:own_draft) { create(:invoice, company:, submitted_by: requester) }
  let!(:own_pending) { create(:invoice, :pending, company:, submitted_by: requester) }
  let!(:others_draft) { create(:invoice, company:, submitted_by: other_requester) }
  let!(:others_approved) { create(:invoice, :approved, company:, submitted_by: other_requester) }
  let!(:foreign_pending) { create(:invoice, :pending) }

  def visible_to(user) = described_class.new(user).resolve

  it "shows a requester only the invoices they authored, including their drafts" do
    expect(visible_to(requester)).to contain_exactly(own_draft, own_pending)
  end

  it "shows approvers and admins every non-draft invoice of their own company" do
    [ approver, admin ].each do |user|
      expect(visible_to(user)).to contain_exactly(own_pending, others_approved)
    end
  end

  it "shows a draft only to its author" do
    viewers = [ requester, other_requester, approver, admin ].select { visible_to(it).include?(own_draft) }
    expect(viewers).to eq([ requester ])
  end

  it "lets only requesters see the draft status at all" do
    expect(InvoicePolicy.visible_statuses(requester)).to include("draft")
    [ approver, admin ].each { expect(InvoicePolicy.visible_statuses(it)).not_to include("draft") }
  end

  it "never crosses companies, whatever the role" do
    foreign_author = foreign_pending.submitted_by
    [ requester, approver, admin ].each { expect(visible_to(it)).not_to include(foreign_pending) }
    expect(visible_to(foreign_author)).to contain_exactly(foreign_pending)
  end
end

RSpec.describe InvoicePolicy do
  let(:company) { create(:company) }
  let(:author) { create(:user, company:) }

  describe "#transition? for approve and reject" do
    %w[approve reject].each do |action|
      Invoice.statuses.each_key do |status|
        { "requester" => false, "approver" => true, "admin" => false }.each do |role, allowed_role|
          expected = allowed_role && status == "pending"
          it "is #{expected} for a non-author #{role} on a #{status} invoice (#{action})" do
            invoice = create(:invoice, company:, submitted_by: author, status: status.upcase)
            actor = create(:user, company:, role:)
            expect(described_class.new(actor, invoice).transition?(action)).to be(expected)
          end
        end
      end

      it "refuses the author even after they become an approver (#{action})" do
        invoice = create(:invoice, :pending, company:, submitted_by: author)
        author.update!(role: "approver")
        policy = described_class.new(author, invoice)
        expect([ policy.permitted?(action), policy.transition?(action) ]).to eq([ false, false ])
      end

      it "refuses an approver of another company (#{action})" do
        invoice = create(:invoice, :pending, company:, submitted_by: author)
        expect(described_class.new(create(:user, :approver), invoice).transition?(action)).to be(false)
      end
    end

    it "keeps permission apart from status, so a decided invoice is a conflict, not a 403" do
      policy = described_class.new(create(:user, :approver, company:), create(:invoice, :approved, company:, submitted_by: author))
      expect([ policy.permitted?("approve"), policy.transition?("approve") ]).to eq([ true, false ])
    end

    it "refuses unknown actions" do
      policy = described_class.new(create(:user, :approver, company:), create(:invoice, :pending, company:, submitted_by: author))
      expect([ policy.permitted?("pay"), policy.transition?("submit") ]).to eq([ false, false ])
    end
  end
end
