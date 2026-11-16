-- The outbox claim orders due work by (next_attempt_at, id). With ~150k queued rows a plain status index forced a
-- full scan and sort on every claim (FOR UPDATE prevents parallel scans), capping delivery near 30 events/s.
-- These partial indexes serve the two claim queries (due work, expired leases) with an ordered index scan.
CREATE INDEX delivery_outbox_due_order ON usage.delivery_outbox(next_attempt_at, id) WHERE status IN ('pending', 'retry');
CREATE INDEX delivery_outbox_expired_leases ON usage.delivery_outbox(lease_until) WHERE status = 'delivering';
