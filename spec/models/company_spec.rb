require "rails_helper"

RSpec.describe Company do
  it "gets a database-generated uuid used as its public param" do
    company = create(:company)
    expect(company.uuid).to be_present
    expect(company.to_param).to eq(company.uuid)
  end

  it "has a unique name" do
    company = create(:company)
    expect { Company.insert!({ name: company.name }) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
