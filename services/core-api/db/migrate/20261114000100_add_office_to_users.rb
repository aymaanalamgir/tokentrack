class AddOfficeToUsers < ActiveRecord::Migration[8.1]
  # Work location as directory metadata (e.g. "Toronto"). It grants nothing and is not part of any financial identity.
  def change
    add_column :users, :office, :string, limit: 80
  end
end
