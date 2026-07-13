# Custom "assess any table" MCP server — container image.
# Built remotely with `az acr build` (no local Docker required on the DevBox).
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8000

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY scoring.py databricks_client.py rulepacks.py server.py ./

EXPOSE 8000

# Streamable-HTTP MCP app is exposed as `app` in server.py; endpoint is /mcp.
CMD ["sh", "-c", "uvicorn server:app --host 0.0.0.0 --port ${PORT}"]
