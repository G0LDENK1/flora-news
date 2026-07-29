#!/bin/bash
# Import all n8n workflows via the n8n API
# Run after n8n is up and configured

N8N_URL="${N8N_URL:-http://localhost:5678}"
N8N_USER="${N8N_BASIC_AUTH_USER:-admin}"
N8N_PASS="${N8N_BASIC_AUTH_PASSWORD:-}"

if [ -z "$N8N_PASS" ]; then
  echo "Set N8N_BASIC_AUTH_PASSWORD in your environment"
  exit 1
fi

WORKFLOW_DIR="./docker/n8n/workflows"

for file in "$WORKFLOW_DIR"/*.json; do
  name=$(basename "$file" .json)
  echo "Importing $name..."
  curl -s -X POST \
    -u "${N8N_USER}:${N8N_PASS}" \
    -H "Content-Type: application/json" \
    -d @"$file" \
    "${N8N_URL}/api/v1/workflows" | jq '.id // .message'
done

echo "✅ Done!"
