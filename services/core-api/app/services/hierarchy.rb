class Hierarchy
  def self.unit_ids(organization_id, roots)
    walk("organizational_units", "parent_unit_id", "id", organization_id, roots)
  end

  def self.report_ids(organization_id, roots, excluding: nil)
    walk("reporting_relationships", "manager_id", "report_id", organization_id, roots, excluding: excluding)
  end

  def self.walk(table, parent, child, organization_id, roots, excluding: nil)
    return [] if roots.empty? || organization_id.blank?
    # Table/column names come only from the two fixed callers; values are quoted by AR.
    connection = ApplicationRecord.connection
    org = connection.quote(organization_id)
    root_list = roots.map { |id| connection.quote(id) + "::uuid" }.join(",")
    exclusion = excluding ? "AND r.id <> #{connection.quote(excluding)}::uuid" : ""
    connection.select_values(<<~SQL)
      WITH RECURSIVE tree(id) AS (
        SELECT unnest(ARRAY[#{root_list}])
        UNION
        SELECT r.#{child} FROM business.#{table} r JOIN tree t ON r.#{parent} = t.id
          WHERE r.organization_id = #{org} #{exclusion}
      ) SELECT id FROM tree
    SQL
  end
  private_class_method :walk
end
