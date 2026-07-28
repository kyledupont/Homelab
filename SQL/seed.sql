-- Real homelab inventory data, mirrored from Docs/Architecture.md (2026-07-15 state)
-- plus later additions (k3s-master01, postgres) confirmed via README.md.

INSERT INTO hosts (name, ip_address, vmid, vcpu, ram_gb, disk_gb, role, status) VALUES
    ('proxmox',      '192.168.1.209', NULL, NULL, 32, NULL, 'hypervisor', 'running'),
    ('automation01', '192.168.1.20',  101,  4,    8,  80,   'automation', 'running'),
    ('truenas01',    '192.168.1.40',  200,  4,    8,  32,   'storage',    'running'),
    ('plex01',       '192.168.1.50',  102,  2,    4,  40,   'media',      'running'),
    ('k3s-master01', '192.168.1.60',  NULL, 2,    4,  40,   'k8s-node',   'running');

INSERT INTO services (host_id, name, container_name, image, compose_path, description, status) VALUES
    ((SELECT id FROM hosts WHERE name = 'automation01'), 'n8n',            'n8n',            'n8nio/n8n',                 'Docker/Automation/docker-compose.yml', 'Workflow automation engine',                          'running'),
    ((SELECT id FROM hosts WHERE name = 'automation01'), 'portainer',      'portainer',      'portainer/portainer-ce',    'Docker/Automation/docker-compose.yml', 'Container management UI, agent-connected to plex01',  'running'),
    ((SELECT id FROM hosts WHERE name = 'automation01'), 'uptime-kuma',    'uptime-kuma',    'louislam/uptime-kuma',      'Docker/Automation/docker-compose.yml', 'Service uptime monitoring',                            'running'),
    ((SELECT id FROM hosts WHERE name = 'automation01'), 'homepage',       'homepage',       'gethomepage/homepage',     'Docker/Automation/docker-compose.yml', 'Dashboard linking every service',                      'running'),
    ((SELECT id FROM hosts WHERE name = 'automation01'), 'mcp-uptime-kuma','mcp-uptime-kuma','custom build',              'Docker/MCP/docker-compose.yml',        'Custom TS MCP server exposing Uptime Kuma as a tool',  'running'),
    ((SELECT id FROM hosts WHERE name = 'automation01'), 'mcp-n8n',        'mcp-n8n',        'ghcr.io/czlonkowski/n8n-mcp','Docker/MCP/docker-compose.yml',      'Community MCP server for n8n node/docs/workflow mgmt', 'running'),
    ((SELECT id FROM hosts WHERE name = 'automation01'), 'postgres',       'postgres',       'postgres:17',               'Docker/Postgres/docker-compose.yml',   'Relational database, NFS-backed via truenas01',        'running'),
    ((SELECT id FROM hosts WHERE name = 'plex01'),       'plex',           'plex',           'plexinc/pms-docker',        'Docker/Media/docker-compose.yml',      'Media server, NFS-mounted from truenas01',             'running'),
    ((SELECT id FROM hosts WHERE name = 'plex01'),       'portainer_agent','portainer_agent','portainer/agent',           'Docker/Media/docker-compose.yml',      'Lets automation01 Portainer manage this host',         'running');

INSERT INTO service_ports (service_id, port_number, protocol, exposed_externally) VALUES
    ((SELECT id FROM services WHERE name = 'n8n'),             5678,  'tcp', true),
    ((SELECT id FROM services WHERE name = 'portainer'),       9443,  'tcp', true),
    ((SELECT id FROM services WHERE name = 'uptime-kuma'),     3001,  'tcp', true),
    ((SELECT id FROM services WHERE name = 'homepage'),        3000,  'tcp', true),
    ((SELECT id FROM services WHERE name = 'mcp-uptime-kuma'), 3100,  'tcp', true),
    ((SELECT id FROM services WHERE name = 'mcp-n8n'),         3101,  'tcp', true),
    ((SELECT id FROM services WHERE name = 'postgres'),        5432,  'tcp', true),
    ((SELECT id FROM services WHERE name = 'plex'),            32400, 'tcp', true),
    ((SELECT id FROM services WHERE name = 'portainer_agent'), 9001,  'tcp', true);

INSERT INTO service_dependencies (service_id, depends_on_id, dependency_type) VALUES
    ((SELECT id FROM services WHERE name = 'mcp-uptime-kuma'), (SELECT id FROM services WHERE name = 'uptime-kuma'), 'runtime'),
    ((SELECT id FROM services WHERE name = 'mcp-n8n'),         (SELECT id FROM services WHERE name = 'n8n'),         'runtime'),
    ((SELECT id FROM services WHERE name = 'homepage'),        (SELECT id FROM services WHERE name = 'n8n'),         'network'),
    ((SELECT id FROM services WHERE name = 'homepage'),        (SELECT id FROM services WHERE name = 'uptime-kuma'), 'network'),
    ((SELECT id FROM services WHERE name = 'homepage'),        (SELECT id FROM services WHERE name = 'portainer'),   'network'),
    ((SELECT id FROM services WHERE name = 'portainer'),       (SELECT id FROM services WHERE name = 'portainer_agent'), 'network');
