-- PRIVILEGES FOR pats USER OF PATS DATABASE
--
-- by Weikun Liang & Mallory Hayase
--

-- SQL needed to create the pats user

CREATE USER pats;

-- SQL to limit pats user access on key tables

REVOKE DELETE ON visit_medicines FROM pats;
REVOKE DELETE ON treatments FROM pats;
REVOKE UPDATE (units_given) ON visit_medicines FROM pats;

GRANT SELECT ON users TO pats;

