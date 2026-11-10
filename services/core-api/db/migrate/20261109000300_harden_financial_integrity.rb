class HardenFinancialIntegrity < ActiveRecord::Migration[8.1]
  def up
    add_check_constraint :financial_transactions, "amount<'Infinity'::numeric", name: "finite_financial_amount"
    add_check_constraint :priced_usage_receipts, "amount<'Infinity'::numeric", name: "finite_receipt_amount"
    add_check_constraint :ledger_entries, "funding_delta>'-Infinity'::numeric AND funding_delta<'Infinity'::numeric AND expense_delta>'-Infinity'::numeric AND expense_delta<'Infinity'::numeric", name: "finite_ledger_deltas"
    add_index :financial_transactions, [:correction_group_id, :kind], unique: true, where: "correction_group_id IS NOT NULL", name: "one_operation_per_correction_side"
    add_check_constraint :financial_transactions, "(kind IN ('reversal','adjustment'))=(original_transaction_id IS NOT NULL) AND (correction_group_id IS NULL OR kind IN ('reversal','adjustment'))", name: "explicit_correction_origin"
    execute <<~SQL
      CREATE FUNCTION business.validate_financial_source() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF NEW.kind='usage_charge' AND NOT EXISTS(SELECT 1 FROM business.priced_usage_receipts r WHERE r.id=NEW.priced_usage_receipt_id AND r.user_id=NEW.user_id AND r.project_id IS NOT DISTINCT FROM NEW.project_id AND NEW.actor_id IS NULL AND NEW.month_start=date_trunc('month',r.occurred_at AT TIME ZONE 'UTC')::date)
        THEN RAISE EXCEPTION 'Financial dimensions and UTC month must match the receipt' USING ERRCODE='23514'; END IF;
        IF NEW.kind IN ('reversal','adjustment') AND NOT EXISTS(SELECT 1 FROM business.financial_transactions o WHERE o.id=NEW.original_transaction_id AND o.user_id IS NOT DISTINCT FROM NEW.user_id AND o.project_id IS NOT DISTINCT FROM NEW.project_id AND o.home_unit_id IS NOT DISTINCT FROM NEW.home_unit_id)
        THEN RAISE EXCEPTION 'Corrections must preserve original attribution' USING ERRCODE='23514'; END IF;
        RETURN NULL;
      END $$;
      CREATE CONSTRAINT TRIGGER financial_source_integrity AFTER INSERT ON business.financial_transactions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION business.validate_financial_source();
    SQL
  end
  def down
    raise ActiveRecord::IrreversibleMigration, "Financial integrity guards protect retained history"
  end
end
