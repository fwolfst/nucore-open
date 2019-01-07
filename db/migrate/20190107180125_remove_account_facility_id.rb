class RemoveAccountFacilityId < ActiveRecord::Migration[5.0]
  def up
    remove_foreign_key :accounts, :facilities
    remove_column :accounts, :facility_id
  end

  def down
    add_reference :accounts, :facility, foreign_key: true, index: true

    # If there happen to be more than one join, then :shrug:, only one will get set.
    execute <<~SQL
      UPDATE accounts
      SET accounts.facility_id = (
        SELECT facility_id
        FROM account_facility_joins
        WHERE accounts.id = account_facility_joins.account_id
      )
    SQL
  end
end
