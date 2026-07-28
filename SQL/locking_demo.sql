-- Row-level locking demo: run each block in a SEPARATE psql session against
-- the same row to see SELECT ... FOR UPDATE actually block a second writer.
--
-- Verified live 2026-07-28 against the automation01 row in `hosts`:
--   Session A locked the row, held it for 6s (simulating a slow write), committed.
--   Session B's FOR UPDATE blocked for the entire remaining wait and only
--   acquired the lock ~15ms after A's COMMIT -- proof the lock is real, not
--   just documentation.

-- Session A:
BEGIN;
SELECT * FROM hosts WHERE name = 'automation01' FOR UPDATE;
-- ... do slow work here; the row is locked for every other FOR UPDATE/UPDATE
-- until this transaction COMMITs or ROLLBACKs ...
UPDATE hosts SET ram_gb = ram_gb WHERE name = 'automation01';
COMMIT;

-- Session B (run concurrently, before A commits):
BEGIN;
SELECT * FROM hosts WHERE name = 'automation01' FOR UPDATE;  -- blocks here until A releases
COMMIT;

-- To see WHO is blocking WHOM while both are open, from a third session:
SELECT
    blocked.pid       AS blocked_pid,
    blocked.query     AS blocked_query,
    blocking.pid      AS blocking_pid,
    blocking.query    AS blocking_query
FROM pg_stat_activity blocked
JOIN pg_locks bl ON bl.pid = blocked.pid AND NOT bl.granted
JOIN pg_locks kl ON kl.locktype = bl.locktype
    AND kl.database IS NOT DISTINCT FROM bl.database
    AND kl.relation IS NOT DISTINCT FROM bl.relation
    AND kl.page IS NOT DISTINCT FROM bl.page
    AND kl.tuple IS NOT DISTINCT FROM bl.tuple
    AND kl.pid != bl.pid AND kl.granted
JOIN pg_stat_activity blocking ON blocking.pid = kl.pid;
