#!/bin/sh
# Idempotent: create hypha.ee primary zone with apex + wildcard → LOCAL_IP.
set -eu

URL="${TECHNITIUM_URL:-http://technitium:5380}"
USER="${TECHNITIUM_USER:-admin}"
PASS="${TECHNITIUM_PASS:?TECHNITIUM_PASS required}"
ZONE="${LOCAL_ZONE:-hypha.ee}"
IP="${LOCAL_IP:-10.53.0.31}"

echo "Waiting for Technitium at ${URL}..."
i=0
while [ "$i" -lt 60 ]; do
  if curl -fsS "${URL}/api/user/login?user=${USER}&pass=${PASS}" >/tmp/login.json 2>/dev/null; then
    break
  fi
  i=$((i + 1))
  sleep 2
done

if ! grep -q '"status":"ok"' /tmp/login.json 2>/dev/null; then
  echo "Technitium login failed:"
  cat /tmp/login.json 2>/dev/null || true
  exit 1
fi

# Response is JSON; extract token without jq (curl image is minimal).
TOKEN=$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' /tmp/login.json)
if [ -z "$TOKEN" ]; then
  echo "Could not parse API token"
  cat /tmp/login.json
  exit 1
fi

echo "Ensuring primary zone ${ZONE}..."
CREATE=$(curl -fsS "${URL}/api/zones/create?token=${TOKEN}&zone=${ZONE}&type=Primary" || true)
case "$CREATE" in
  *'"status":"ok"'*|*already*|*exists*|*ZoneAlreadyExists*|*duplicate*)
    echo "Zone ready (${CREATE})"
    ;;
  *)
    # create may fail if zone exists; list to confirm
    LIST=$(curl -fsS "${URL}/api/zones/list?token=${TOKEN}")
    case "$LIST" in
      *"${ZONE}"*) echo "Zone already present" ;;
      *)
        echo "Zone create failed: ${CREATE}"
        echo "Zones: ${LIST}"
        exit 1
        ;;
    esac
    ;;
esac

add_a() {
  domain="$1"
  echo "Upserting A ${domain} → ${IP}"
  curl -fsS \
    "${URL}/api/zones/records/add?token=${TOKEN}&domain=${domain}&zone=${ZONE}&type=A&ipAddress=${IP}&ttl=300&overwrite=true" \
    >/dev/null
}

add_a "${ZONE}"
add_a "*.${ZONE}"

echo "Local DNS for *.${ZONE} → ${IP} configured."
