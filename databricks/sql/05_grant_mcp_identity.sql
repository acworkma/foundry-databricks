-- ===========================================================================
-- 05_grant_mcp_identity.sql
-- Authorize the Foundry agent's identity to call the Unity Catalog functions
-- through the functions managed MCP server.
--
-- The recommended auth for the UC Functions MCP tool is Microsoft Entra with
-- the Foundry *project's managed identity* (a service identity: no user
-- sign-in, no OAuth app, no PAT). That identity must exist in this workspace
-- as a service principal and hold privileges on the functions' schema.
--
-- Run this in a SQL editor (replace the placeholders below), or via run_sql.py
-- which substitutes ${CATALOG} / ${SCHEMA}. Placeholders (defaults):
--   ${CATALOG} = datahub_demo, ${SCHEMA} = quality
--
-- Before running, in the Databricks workspace (Settings > Identity and access >
-- Service principals) add the project managed identity as a **Microsoft Entra
-- managed** service principal using its Application (client) ID, and give it
-- Workspace access. Then set the two placeholders below:
--   <project-mi-app-id>  = the Foundry project managed identity Application ID
--   <function-owner>     = the principal that owns the functions/tables
--                          (see the discovery query in section 2)
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. Grant the Foundry project managed identity access to the functions.
--    SELECT/EXECUTE on the schema cascade to every table and function in it.
-- ---------------------------------------------------------------------------
GRANT USE CATALOG ON CATALOG ${CATALOG} TO `<project-mi-app-id>`;
GRANT USE SCHEMA, SELECT, EXECUTE ON SCHEMA ${CATALOG}.${SCHEMA} TO `<project-mi-app-id>`;

-- ---------------------------------------------------------------------------
-- 2. Ownership chaining.
--    A Unity Catalog SQL function runs its body with the FUNCTION OWNER's
--    identity, not the caller's. If ${CATALOG} is a workspace *default catalog*
--    (owned by a workspace-admins group), the owner may hold catalog access
--    only implicitly, which breaks the chain and fails at call time with:
--      [INSUFFICIENT_PERMISSIONS] ... the owner of one of the underlying
--      resources failed an authorization check  (SQLSTATE 42501)
--    Grant the owner explicit privileges down the chain once.
--
--    Find the owner first, then substitute <function-owner> below:
--      SELECT DISTINCT routine_owner
--        FROM ${CATALOG}.information_schema.routines
--       WHERE specific_schema = '${SCHEMA}';
-- ---------------------------------------------------------------------------
GRANT USE CATALOG ON CATALOG ${CATALOG} TO `<function-owner>`;
GRANT USE SCHEMA, SELECT, EXECUTE ON SCHEMA ${CATALOG}.${SCHEMA} TO `<function-owner>`;

-- ---------------------------------------------------------------------------
-- 3. Verify (optional). Both principals should appear with USE_SCHEMA / SELECT
--    / EXECUTE, and both with USE_CATALOG on the catalog.
-- ---------------------------------------------------------------------------
-- SELECT grantee, privilege_type
--   FROM ${CATALOG}.information_schema.schema_privileges
--  WHERE catalog_name = '${CATALOG}' AND schema_name = '${SCHEMA}'
--  ORDER BY 1, 2;
