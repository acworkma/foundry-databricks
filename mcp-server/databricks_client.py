"""Minimal Databricks SQL Statement Execution API client.

Standard-library only. Every call takes the **caller's** OAuth bearer token
(forwarded by Foundry via OAuth Identity Passthrough) so the query runs as the
signed-in user and Unity Catalog enforces that user's grants. The server never
holds a static credential of its own for data access.
"""
from __future__ import annotations

import json
import time
import urllib.error
import urllib.request
from typing import Any, Optional


class DatabricksError(RuntimeError):
    """Raised when a statement fails or the API returns an error."""


class DatabricksSqlClient:
    def __init__(self, host: str, warehouse_id: str, *, poll_interval: float = 1.5,
                 max_wait_seconds: float = 110.0):
        # host is the bare workspace hostname or full https URL.
        host = host.strip().rstrip("/")
        if not host.startswith("http"):
            host = "https://" + host
        self._api = f"{host}/api/2.0/sql/statements"
        self._warehouse_id = warehouse_id
        self._poll_interval = poll_interval
        self._max_wait_seconds = max_wait_seconds

    def _headers(self, token: str) -> dict:
        return {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        }

    def _request(self, url: str, token: str, *, data: Optional[bytes] = None,
                 method: str = "GET") -> dict:
        req = urllib.request.Request(url, data=data, headers=self._headers(token), method=method)
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", "replace")[:500]
            if exc.code in (401, 403):
                raise DatabricksError(
                    "Databricks rejected the request (auth). Ensure the calling user is a "
                    f"Databricks principal with Unity Catalog grants. HTTP {exc.code}: {body}"
                ) from exc
            raise DatabricksError(f"HTTP {exc.code}: {body}") from exc

    def execute(self, statement: str, token: str) -> dict:
        """Submit a statement, poll to completion, and return the raw API result."""
        body = json.dumps({
            "warehouse_id": self._warehouse_id,
            "statement": statement,
            "wait_timeout": "30s",
            "on_wait_timeout": "CONTINUE",
            "format": "JSON_ARRAY",
            "disposition": "INLINE",
        }).encode()
        result = self._request(self._api, token, data=body, method="POST")

        statement_id = result.get("statement_id")
        state = result.get("status", {}).get("state")
        deadline = time.time() + self._max_wait_seconds
        while state in ("PENDING", "RUNNING"):
            if time.time() > deadline:
                raise DatabricksError(f"Statement {statement_id} timed out in state {state}.")
            time.sleep(self._poll_interval)
            result = self._request(f"{self._api}/{statement_id}", token)
            state = result.get("status", {}).get("state")

        if state != "SUCCEEDED":
            err = result.get("status", {}).get("error", {})
            raise DatabricksError(f"Statement failed ({state}): {err.get('message', 'unknown error')}")
        return result

    def fetch_all(self, statement: str, token: str) -> tuple[list[str], list[list[Any]]]:
        """Run a query and return (column_names, rows)."""
        result = self.execute(statement, token)
        manifest = result.get("manifest", {})
        columns = [c.get("name", "") for c in manifest.get("schema", {}).get("columns", [])]
        rows = result.get("result", {}).get("data_array", []) or []
        return columns, rows

    def fetch_one(self, statement: str, token: str) -> Optional[dict]:
        """Run a query expected to return a single row; return it as a dict (or None)."""
        columns, rows = self.fetch_all(statement, token)
        if not rows:
            return None
        return dict(zip(columns, rows[0]))
