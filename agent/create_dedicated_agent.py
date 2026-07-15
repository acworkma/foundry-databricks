#!/usr/bin/env python3
"""Create the dedicated Data Quality Agent and its custom MCP tool connection.

This is the code-driven counterpart to the portal click-path documented in
`docs/integration/custom-mcp-server.md`. It performs two data-plane operations
that Bicep/ARM templates cannot express declaratively:

  1. Creates (or updates) an OAuth2 "RemoteTool" **connection** on the Foundry
     project that points at the private custom MCP server and carries the
     Custom OAuth Identity Passthrough configuration (Entra app + Azure
     Databricks scope).
  2. Creates a dedicated **prompt agent** whose only tool is the custom MCP
     server, bound to that connection.

Everything is parameterised from environment variables so the script contains
no environment-specific values. It uses only the Python standard library; it
shells out to the Azure CLI (`az`) purely to obtain access tokens (or you can
supply the tokens directly via env vars).

Required environment variables:
  AZURE_SUBSCRIPTION_ID     the subscription holding the Foundry account
  FOUNDRY_RESOURCE_GROUP    resource group of the Foundry account
  FOUNDRY_ACCOUNT           Foundry (Cognitive Services) account name
  FOUNDRY_PROJECT           Foundry project name
  FOUNDRY_ENDPOINT          project data-plane host, e.g.
                            https://<account>.services.ai.azure.com
  MCP_SERVER_URL            the custom MCP server endpoint, e.g.
                            https://<app-fqdn>/mcp
  ENTRA_TENANT_ID           tenant GUID hosting the OAuth app registration
  OAUTH_CLIENT_ID           app (client) ID of the Entra OAuth app
  OAUTH_CLIENT_SECRET       client secret for that app

Optional environment variables (sensible defaults shown):
  CONNECTION_NAME           databricks-custom-mcp
  AGENT_NAME                data-quality-agent-dedicated
  AGENT_MODEL               gpt-4.1   (must be a deployment in the project)
  SERVER_LABEL              databricks-custom-mcp
  AGENT_INSTRUCTIONS_FILE   agent/instructions-custom-mcp.md
  OAUTH_SCOPE               "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d/user_impersonation offline_access"
                            (2ff814a6... is the PUBLIC Azure Databricks
                            first-party application ID; offline_access enables
                            token refresh)
  ARM_TOKEN / FOUNDRY_TOKEN pre-fetched bearer tokens (skip the az calls)

Usage:
  python create_dedicated_agent.py

Post-steps that remain interactive (documented, not scriptable):
  * Register the redirect URL that Foundry generates for the connection on the
    Entra app (Authentication blade / `az ad app update --web-redirect-uris`).
  * Sign in once in the Playground to complete the per-user OAuth consent so
    your Azure Databricks token is forwarded on each call.
"""
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

DATABRICKS_APP_ID = "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d"  # public first-party app
ARM_API_VERSION = "2025-06-01"
AGENTS_API_VERSION = "v1"


def env(name, default=None, required=False):
    val = os.environ.get(name, default)
    if required and not val:
        sys.exit(f"ERROR: environment variable {name} is required")
    return val


def get_token(scope, override_env):
    """Return a bearer token for the given scope, preferring an env override."""
    pre = os.environ.get(override_env)
    if pre:
        return pre.strip()
    try:
        out = subprocess.check_output(
            ["az", "account", "get-access-token", "--scope", scope,
             "--query", "accessToken", "-o", "tsv"],
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        sys.exit(f"ERROR: could not obtain token for {scope}: {exc}")
    return out.strip()


def request(url, token, method="GET", body=None):
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"HTTP {exc.code} {method} {url}\n{exc.read().decode()[:800]}")


def create_connection(cfg, arm_token):
    url = (
        f"https://management.azure.com/subscriptions/{cfg['sub']}"
        f"/resourceGroups/{cfg['rg']}/providers/Microsoft.CognitiveServices"
        f"/accounts/{cfg['account']}/projects/{cfg['project']}"
        f"/connections/{cfg['conn']}?api-version={ARM_API_VERSION}"
    )
    authority = f"https://login.microsoftonline.com/{cfg['tenant']}/oauth2/v2.0"
    body = {
        "properties": {
            "authType": "OAuth2",
            "category": "RemoteTool",
            "target": cfg["mcp_url"],
            "credentials": {
                "clientId": cfg["client_id"],
                "clientSecret": cfg["client_secret"],
            },
            "metadata": {
                "authorizationUrl": f"{authority}/authorize",
                "tokenUrl": f"{authority}/token",
                "refreshUrl": f"{authority}/token",
                "scope": cfg["scope"],
                "type": "custom_MCP",
            },
        }
    }
    status, _ = request(url, arm_token, method="PUT", body=body)
    print(f"[connection] {cfg['conn']} -> HTTP {status}")


def create_agent(cfg, foundry_token):
    base = cfg["endpoint"].rstrip("/")
    project_url = f"{base}/api/projects/{cfg['project']}"
    url = f"{project_url}/agents?api-version={AGENTS_API_VERSION}"
    body = {
        "name": cfg["agent"],
        "description": "Dedicated data quality agent using the custom MCP server "
                       "(dedicated Pro warehouse, private, per-user governance).",
        "definition": {
            "kind": "prompt",
            "model": cfg["model"],
            "instructions": cfg["instructions"],
            "tools": [
                {
                    "type": "mcp",
                    "server_label": cfg["server_label"],
                    "server_url": cfg["mcp_url"],
                    "require_approval": "never",
                    "project_connection_id": cfg["conn"],
                }
            ],
        },
    }
    # DELETE first so re-runs replace tools cleanly (PATCH only edits metadata).
    try:
        request(f"{project_url}/agents/{cfg['agent']}?api-version={AGENTS_API_VERSION}",
                foundry_token, method="DELETE")
        print(f"[agent] removed existing {cfg['agent']}")
    except RuntimeError:
        pass
    status, _ = request(url, foundry_token, method="POST", body=body)
    print(f"[agent] {cfg['agent']} -> HTTP {status}")


def main():
    instructions_file = env("AGENT_INSTRUCTIONS_FILE", "agent/instructions-custom-mcp.md")
    try:
        with open(instructions_file, "r", encoding="utf-8") as fh:
            instructions = fh.read()
    except OSError as exc:
        sys.exit(f"ERROR: cannot read instructions file {instructions_file}: {exc}")

    cfg = {
        "sub": env("AZURE_SUBSCRIPTION_ID", required=True),
        "rg": env("FOUNDRY_RESOURCE_GROUP", required=True),
        "account": env("FOUNDRY_ACCOUNT", required=True),
        "project": env("FOUNDRY_PROJECT", required=True),
        "endpoint": env("FOUNDRY_ENDPOINT", required=True),
        "mcp_url": env("MCP_SERVER_URL", required=True),
        "tenant": env("ENTRA_TENANT_ID", required=True),
        "client_id": env("OAUTH_CLIENT_ID", required=True),
        "client_secret": env("OAUTH_CLIENT_SECRET", required=True),
        "conn": env("CONNECTION_NAME", "databricks-custom-mcp"),
        "agent": env("AGENT_NAME", "data-quality-agent-dedicated"),
        "model": env("AGENT_MODEL", "gpt-4.1"),
        "server_label": env("SERVER_LABEL", "databricks-custom-mcp"),
        "scope": env(
            "OAUTH_SCOPE",
            f"{DATABRICKS_APP_ID}/user_impersonation offline_access",
        ),
        "instructions": instructions,
    }

    arm_token = get_token("https://management.azure.com/.default", "ARM_TOKEN")
    foundry_token = get_token("https://ai.azure.com/.default", "FOUNDRY_TOKEN")

    create_connection(cfg, arm_token)
    create_agent(cfg, foundry_token)

    print("\nDone. Remaining interactive post-steps:")
    print("  1. Register the Foundry-generated redirect URL on the Entra app.")
    print("  2. Sign in once in the Playground to complete the OAuth consent.")


if __name__ == "__main__":
    main()
