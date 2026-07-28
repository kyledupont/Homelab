-- EXPLAIN ANALYZE demo: indexes only matter at scale. The real inventory
-- tables (9 services) are too small to show a seq-scan-vs-index-scan
-- difference -- Postgres correctly prefers a seq scan there. This table
-- simulates 2M rows of health-check history (what mcp-uptime-kuma-style
-- polling would produce over time) to make the effect real and measurable.

CREATE TABLE query_log (
    id                BIGSERIAL PRIMARY KEY,
    service_id        INTEGER NOT NULL REFERENCES services(id),
    queried_at        TIMESTAMPTZ NOT NULL,
    response_time_ms  INTEGER NOT NULL,
    status_code       INTEGER NOT NULL
);

-- 2,000,000 synthetic rows spread across the 9 real services over ~60 days.
INSERT INTO query_log (service_id, queried_at, response_time_ms, status_code)
SELECT
    (floor(random() * 9) + 1)::int,
    now() - (random() * interval '60 days'),
    (random() * 500)::int,
    CASE WHEN random() < 0.02 THEN 500 ELSE 200 END
FROM generate_series(1, 2000000);
