-- Homelab inventory schema.
-- Real documentation of the lab (see Docs/Architecture.md), not a toy exercise --
-- doubles as SQL practice: multi-table joins, FKs, indexes, self-referential deps.

CREATE TABLE hosts (
    id            SERIAL PRIMARY KEY,
    name          TEXT NOT NULL UNIQUE,
    ip_address    INET NOT NULL UNIQUE,
    vmid          INTEGER,                  -- Proxmox VMID, NULL for the bare-metal host itself
    vcpu          INTEGER,
    ram_gb        INTEGER,
    disk_gb       INTEGER,
    role          TEXT NOT NULL,             -- e.g. 'automation', 'media', 'storage', 'k8s-node', 'hypervisor'
    status        TEXT NOT NULL DEFAULT 'running' CHECK (status IN ('running', 'stopped', 'planned')),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE services (
    id            SERIAL PRIMARY KEY,
    host_id       INTEGER NOT NULL REFERENCES hosts(id) ON DELETE CASCADE,
    name          TEXT NOT NULL,
    container_name TEXT,
    image         TEXT,
    compose_path  TEXT,
    description   TEXT,
    status        TEXT NOT NULL DEFAULT 'running' CHECK (status IN ('running', 'stopped', 'planned')),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (host_id, name)
);

CREATE TABLE service_ports (
    id            SERIAL PRIMARY KEY,
    service_id    INTEGER NOT NULL REFERENCES services(id) ON DELETE CASCADE,
    port_number   INTEGER NOT NULL CHECK (port_number BETWEEN 1 AND 65535),
    protocol      TEXT NOT NULL DEFAULT 'tcp' CHECK (protocol IN ('tcp', 'udp')),
    exposed_externally BOOLEAN NOT NULL DEFAULT true
);

-- Self-referential many-to-many: which services depend on which other services.
-- e.g. mcp-uptime-kuma depends on uptime-kuma being reachable.
CREATE TABLE service_dependencies (
    service_id      INTEGER NOT NULL REFERENCES services(id) ON DELETE CASCADE,
    depends_on_id   INTEGER NOT NULL REFERENCES services(id) ON DELETE CASCADE,
    dependency_type TEXT NOT NULL DEFAULT 'runtime',  -- 'runtime', 'network', 'data'
    PRIMARY KEY (service_id, depends_on_id),
    CHECK (service_id <> depends_on_id)
);

-- Indexes on FK columns are NOT automatic in Postgres (unlike the PK side) --
-- added deliberately here, see SQL/explain_demo.sql for the before/after EXPLAIN ANALYZE.
CREATE INDEX idx_services_host_id ON services(host_id);
CREATE INDEX idx_service_ports_service_id ON service_ports(service_id);
CREATE INDEX idx_service_deps_service_id ON service_dependencies(service_id);
CREATE INDEX idx_service_deps_depends_on_id ON service_dependencies(depends_on_id);
