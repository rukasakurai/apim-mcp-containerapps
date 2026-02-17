#!/usr/bin/env bash
# test-mcp-endpoint.sh — End-to-end smoke test for an MCP server endpoint.
#
# Validates that an MCP server exposed through Azure API Management responds
# correctly to standard MCP protocol requests (Streamable HTTP transport).
#
# Usage:
#   ./tests/test-mcp-endpoint.sh <MCP_SERVER_URL>
#
# Options (via environment variables):
#   MAX_RETRIES       — Number of readiness retries (default: 30)
#   RETRY_INTERVAL    — Seconds between retries  (default: 10)
#
# Exit codes:
#   0  All tests passed
#   1  One or more tests failed

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
MCP_URL="${1:?Usage: $0 <MCP_SERVER_URL>}"
MAX_RETRIES="${MAX_RETRIES:-30}"
RETRY_INTERVAL="${RETRY_INTERVAL:-10}"

PASS=0
FAIL=0
SESSION_ID=""
FIRST_TOOL_NAME=""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { echo "ℹ️  $*"; }
pass()  { echo "✅ $*"; PASS=$((PASS + 1)); }
fail()  { echo "❌ $*"; FAIL=$((FAIL + 1)); }
fatal() { echo "💥 $*" >&2; exit 1; }

# Send a JSON-RPC request to the MCP endpoint and capture response + headers.
# Globals: SESSION_ID (read), MCP_URL (read)
# Arguments: $1 = JSON body
# Outputs:  Sets RESPONSE_BODY, RESPONSE_CODE, RESPONSE_HEADERS, CURL_STDERR
mcp_request() {
  local body="$1"
  local tmp_headers tmp_stderr
  tmp_headers=$(mktemp)
  tmp_stderr=$(mktemp)

  local -a curl_args=(
    --silent
    --show-error
    --max-time 30
    --write-out "\n%{http_code}"
    --dump-header "$tmp_headers"
    --header "Content-Type: application/json"
    --header "Accept: application/json, text/event-stream"
    --data "$body"
  )

  # Include session header if we have one from a previous response
  if [[ -n "$SESSION_ID" ]]; then
    curl_args+=(--header "Mcp-Session-Id: $SESSION_ID")
  fi

  local raw
  raw=$(curl "${curl_args[@]}" "$MCP_URL" 2>"$tmp_stderr") || true

  # Last line is the HTTP status code (from --write-out)
  RESPONSE_CODE=$(echo "$raw" | tail -n1)
  RESPONSE_BODY=$(echo "$raw" | sed '$d')
  RESPONSE_HEADERS=$(cat "$tmp_headers")
  CURL_STDERR=$(cat "$tmp_stderr")
  rm -f "$tmp_headers" "$tmp_stderr"

  if [[ -n "$CURL_STDERR" ]]; then
    info "  curl stderr: $CURL_STDERR"
  fi

  # Extract Mcp-Session-Id header if present (case-insensitive)
  local sid
  sid=$(echo "$RESPONSE_HEADERS" | grep -i '^mcp-session-id:' | head -1 | sed 's/^[^:]*: *//;s/\r$//' || true)
  if [[ -n "$sid" ]]; then
    SESSION_ID="$sid"
  fi
}

# Extract the JSON body from the response, handling SSE format.
# Outputs the JSON string to stdout.
get_response_json() {
  local body="$RESPONSE_BODY"

  # If the body looks like SSE, extract the last data: line's JSON
  if echo "$body" | grep -q '^data: '; then
    echo "$body" | grep '^data: ' | tail -1 | sed 's/^data: //'
  else
    echo "$body"
  fi
}

# Parse a dotted field path from the response JSON using jq.
# Arguments: $1 = dotted field path (e.g. "result.protocolVersion")
parse_json_field() {
  local field="$1"
  local json
  json=$(get_response_json)

  # Convert dotted path to jq path (e.g. "result.protocolVersion" -> ".result.protocolVersion")
  local jq_path=".${field}"

  echo "$json" | jq -r "$jq_path // empty" 2>/dev/null || echo ""
}

# ---------------------------------------------------------------------------
# Wait for endpoint readiness
# ---------------------------------------------------------------------------
wait_for_ready() {
  info "Waiting for MCP endpoint to become ready: $MCP_URL"
  info "Will retry up to $MAX_RETRIES times, every ${RETRY_INTERVAL}s"

  for i in $(seq 1 "$MAX_RETRIES"); do
    # Send a real MCP initialize request. We wait until we get a 2xx back,
    # which confirms APIM is up AND the MCP API route has propagated.
    # 404 means APIM is responding but the MCP API isn't registered yet.
    local code
    code=$(curl --silent --output /dev/null --write-out "%{http_code}" \
      --max-time 10 \
      --header "Content-Type: application/json" \
      --header "Accept: application/json, text/event-stream" \
      --data '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"readiness-probe","version":"0.0.1"}}}' \
      "$MCP_URL" 2>/dev/null) || code="000"

    if [[ "$code" =~ ^2[0-9]{2}$ ]]; then
      pass "Endpoint ready (HTTP $code) after $i attempt(s)"
      return 0
    fi
    info "  Attempt $i/$MAX_RETRIES — HTTP $code, retrying in ${RETRY_INTERVAL}s..."
    sleep "$RETRY_INTERVAL"
  done

  fatal "Endpoint not ready after $MAX_RETRIES attempts"
}

# ---------------------------------------------------------------------------
# Test 1: MCP initialize
# ---------------------------------------------------------------------------
test_initialize() {
  info "Test: MCP initialize"

  local body
  body=$(cat <<'EOF'
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2025-03-26",
    "capabilities": {},
    "clientInfo": {
      "name": "ci-test-client",
      "version": "1.0.0"
    }
  }
}
EOF
)

  mcp_request "$body"

  # Check HTTP status
  if [[ "$RESPONSE_CODE" =~ ^2[0-9]{2}$ ]]; then
    pass "initialize returned HTTP $RESPONSE_CODE"
  else
    fail "initialize returned HTTP $RESPONSE_CODE (expected 2xx)"
    info "  Response body: $RESPONSE_BODY"
    return
  fi

  # Check JSON-RPC response structure
  local jsonrpc_version
  jsonrpc_version=$(parse_json_field "jsonrpc")
  if [[ "$jsonrpc_version" == "2.0" ]]; then
    pass "initialize response has jsonrpc: 2.0"
  else
    fail "initialize response missing jsonrpc: 2.0 (got: '$jsonrpc_version')"
  fi

  # Check that result contains protocolVersion
  local proto
  proto=$(parse_json_field "result.protocolVersion")
  if [[ -n "$proto" ]]; then
    pass "initialize returned protocolVersion: $proto"
  else
    fail "initialize response missing result.protocolVersion"
  fi

  # Check that result contains serverInfo
  local server_name
  server_name=$(parse_json_field "result.serverInfo.name")
  if [[ -n "$server_name" ]]; then
    pass "initialize returned serverInfo.name: $server_name"
  else
    fail "initialize response missing result.serverInfo.name"
  fi

  # Send initialized notification (required by MCP protocol)
  info "  Sending initialized notification"
  mcp_request '{"jsonrpc":"2.0","method":"notifications/initialized"}'
}

# ---------------------------------------------------------------------------
# Test 2: MCP tools/list
# ---------------------------------------------------------------------------
test_tools_list() {
  info "Test: MCP tools/list"

  local body
  body=$(cat <<'EOF'
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/list",
  "params": {}
}
EOF
)

  mcp_request "$body"

  # Check HTTP status
  if [[ "$RESPONSE_CODE" =~ ^2[0-9]{2}$ ]]; then
    pass "tools/list returned HTTP $RESPONSE_CODE"
  else
    fail "tools/list returned HTTP $RESPONSE_CODE (expected 2xx)"
    info "  Response body: $RESPONSE_BODY"
    return
  fi

  # Check that result.tools is present and is a list
  local json tools_count
  json=$(get_response_json)
  tools_count=$(echo "$json" | jq '.result.tools | length' 2>/dev/null || echo "-1")

  if [[ "$tools_count" -ge 0 ]]; then
    pass "tools/list returned $tools_count tool(s)"
  else
    fail "tools/list response missing result.tools array"
    info "  Response body: $RESPONSE_BODY"
  fi

  # Save the first tool name for the tools/call test
  if [[ "$tools_count" -gt 0 ]]; then
    FIRST_TOOL_NAME=$(echo "$json" | jq -r '.result.tools[0].name' 2>/dev/null || echo "")
    info "  First tool: $FIRST_TOOL_NAME"
  fi
}

# ---------------------------------------------------------------------------
# Test 3: MCP tools/call — invoke the first tool from the list
# ---------------------------------------------------------------------------
test_tools_call() {
  if [[ -z "$FIRST_TOOL_NAME" ]]; then
    info "Test: MCP tools/call — SKIPPED (no tools available)"
    return
  fi

  info "Test: MCP tools/call ($FIRST_TOOL_NAME)"

  # Build a minimal tools/call request. We pass empty arguments — the goal is
  # to verify that APIM proxies the request to the backend and returns a valid
  # JSON-RPC response. Even an error response (e.g. missing required argument)
  # proves the full proxy path works.
  local body
  body=$(jq -n \
    --arg tool "$FIRST_TOOL_NAME" \
    '{
      jsonrpc: "2.0",
      id: 3,
      method: "tools/call",
      params: {
        name: $tool,
        arguments: {}
      }
    }')

  mcp_request "$body"

  # Check HTTP status — any 2xx is fine
  if [[ "$RESPONSE_CODE" =~ ^2[0-9]{2}$ ]]; then
    pass "tools/call returned HTTP $RESPONSE_CODE"
  else
    fail "tools/call returned HTTP $RESPONSE_CODE (expected 2xx)"
    info "  Response body: $RESPONSE_BODY"
    return
  fi

  # Verify it's a valid JSON-RPC response (has either result or error)
  local json has_result has_error
  json=$(get_response_json)
  has_result=$(echo "$json" | jq 'has("result")' 2>/dev/null || echo "false")
  has_error=$(echo "$json" | jq 'has("error")' 2>/dev/null || echo "false")

  if [[ "$has_result" == "true" ]]; then
    pass "tools/call returned a result"
  elif [[ "$has_error" == "true" ]]; then
    # An error response is acceptable — it means the proxy path works,
    # the backend just rejected the (empty) arguments.
    local error_msg
    error_msg=$(echo "$json" | jq -r '.error.message // "unknown"' 2>/dev/null)
    pass "tools/call returned a JSON-RPC error (expected with empty args): $error_msg"
  else
    fail "tools/call response is not a valid JSON-RPC response (no result or error)"
    info "  Response body: $RESPONSE_BODY"
  fi
}
# Main
# ---------------------------------------------------------------------------
main() {
  echo "========================================"
  echo " MCP Endpoint Integration Tests"
  echo " URL: $MCP_URL"
  echo "========================================"
  echo ""

  wait_for_ready

  echo ""
  test_initialize

  echo ""
  test_tools_list

  echo ""
  test_tools_call

  echo ""
  echo "========================================"
  echo " Results: $PASS passed, $FAIL failed"
  echo "========================================"

  if [[ "$FAIL" -gt 0 ]]; then
    exit 1
  fi
}

main
