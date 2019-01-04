class AccountFacilityJoin < ApplicationRecord

  belongs_to :facility
  belongs_to :account
  belongs_to :created_by, class_name: "User"

end
