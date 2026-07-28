# SQL

## Why this is in the plan

PostgreSQL was deployed via Ansible on 2026-07-23 (see [Ansible.md](Ansible.md)) and confirmed reachable, but "the container is healthy" isn't the same as "I know SQL" — the checklist gap was schema design, indexing, query-plan reading, and transactions/locking, none of which a bare `pg_isready` exercises. This is that gap closed with real exercises against the live instance, not a tutorial sandbox.

Status: **Schema designed, seeded, and all three exercises (indexing, EXPLAIN ANALYZE, row locking) run live against `postgres` on `automation01` — 2026-07-28.**

## What's built

All SQL lives in [`SQL/`](../SQL/):

- [`schema.sql`](../SQL/schema.sql) — a real homelab inventory schema, not a toy: `hosts` → `services` → `service_ports` (one-to-many) plus a self-referential `service_dependencies` many-to-many (e.g. `mcp-uptime-kuma` depends on `uptime-kuma`). Indexes added deliberately on every FK column — worth knowing that **Postgres does not auto-index foreign key columns** (unlike the primary-key side of the relationship), so an unindexed FK is a real, common production gotcha, not a contrived one.
- [`seed.sql`](../SQL/seed.sql) — populated with the lab's actual hosts/services/ports pulled from [Architecture.md](Architecture.md), so `SELECT * FROM services JOIN hosts ...` returns the real service/port map instead of fake rows. Doubles as documentation that stays queryable.
- [`explain_demo.sql`](../SQL/explain_demo.sql) — a synthetic 2,000,000-row `query_log` table (simulated health-check history). The real inventory tables are too small (9 services) for the planner to ever prefer an index over a sequential scan — indexing only matters at scale, so this table exists to make that scale real.
- [`locking_demo.sql`](../SQL/locking_demo.sql) — `SELECT ... FOR UPDATE` row-locking pattern, plus a `pg_locks`/`pg_stat_activity` query to see who's blocking whom.

## Exercises run, with real numbers

**1. FK index, before/after** — `SELECT * FROM query_log WHERE service_id = 5 AND status_code = 500` (2M rows):
- No index: parallel sequential scan, **46.9ms**, 14,706 buffer reads.
- With `idx_query_log_service_status` (composite on `service_id, status_code`): bitmap heap scan, **2.96ms**, 3,839 buffer reads. **~16x faster.**

**2. The "wrapped column" gotcha** — an index on `queried_at` exists in both queries below, but only one query can actually use it:
- `WHERE queried_at::date = '2026-07-01'` — wrapping the column in `::date` makes it non-sargable (the *function result* isn't what's indexed). Forces a full parallel seq scan: **67.9ms**.
- `WHERE queried_at >= '2026-07-01' AND queried_at < '2026-07-02'` — same logical filter, rewritten as a sargable range. Index-only scan: **4.1ms**. **~16x faster**, same index, same data — only the query shape changed. This is a real diagnosis skill: `EXPLAIN ANALYZE` showing `Seq Scan` where you expected an `Index Scan` is the first thing to check when a query is unexpectedly slow.

**3. Row-level locking, proven with wall-clock timestamps** — two concurrent sessions against the same row (`hosts` where `name = 'automation01'`):
- Session A: `BEGIN; SELECT ... FOR UPDATE;` at `23:06:20.489`, held for 6s (simulating slow work), `COMMIT` at `23:06:26.495`.
- Session B: opened its own `BEGIN; SELECT ... FOR UPDATE;` at `23:06:21.9` (while A still held the lock) — **blocked** until A committed, then acquired the lock at `23:06:26.511`, ~15ms after A released it. `time` on session B's whole `ssh` round-trip measured **5.05s** of real wait. This is a genuine, timed demonstration that Postgres row locks serialize concurrent writers rather than just documenting that they "should."

## How to connect and keep practicing

Postgres isn't exposed to the internet — connect via SSH to `automation01` (see [Commands.md](Commands.md) for the key-based SSH pattern), then:

```bash
ssh kyle@192.168.1.20
docker exec -it postgres psql -U postgres -d postgres
```

Or non-interactively from the Windows workstation without a local `psql` install:

```bash
ssh kyle@192.168.1.20 "docker exec postgres psql -U postgres -d postgres -c 'SELECT ...'"
```

To re-run any exercise from scratch: `cat SQL/schema.sql | ssh kyle@192.168.1.20 "docker exec -i postgres psql -U postgres -d postgres -v ON_ERROR_STOP=1"` (swap in `seed.sql`/`explain_demo.sql`/`locking_demo.sql` as needed).

## Open questions / next steps

- [ ] Wire n8n's native Postgres node into the `Daily Job & Learning Digest` workflow (e.g. log each run to a table) so SQL becomes part of an existing automation, not just a standalone exercise.
- [ ] Add the `pgvector` extension once local AI (Ollama) exists, to serve as the vector store for the planned RAG exercise — see [AI.md](AI.md).
- [ ] `query_log` is ~214MB of synthetic data — fine for now, but worth dropping/regenerating if disk pressure on `automation01`'s NFS-backed `/mnt/postgres` ever becomes a concern.
