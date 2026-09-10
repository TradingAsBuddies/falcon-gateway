#!/usr/bin/env bash
#
# Generate the Traefik basicAuth users file for the dashboard router.
#
# MUST be run before deploying the auth middleware. Traefik refuses to load a
# basicAuth middleware whose usersFile is missing, and both the `dashboard` and
# `lan-catchall` routers reference `dashboard-auth` -- so without this file the
# trading dashboard is unreachable, not merely unauthenticated.
#
# Usage:
#   ./scripts/generate-htpasswd.sh falcon                 # prompts for password
#   ./scripts/generate-htpasswd.sh falcon 'the-password'  # non-interactive
#
# The output file is gitignored. Never commit it.

set -euo pipefail

USER_NAME="${1:-falcon}"
OUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/configs/traefik/dynamic/users.htpasswd"

if [[ $# -ge 2 ]]; then
  PASSWORD="$2"
else
  read -r -s -p "Password for '${USER_NAME}': " PASSWORD; echo
  read -r -s -p "Confirm: " CONFIRM; echo
  if [[ "$PASSWORD" != "$CONFIRM" ]]; then
    echo "error: passwords do not match" >&2
    exit 1
  fi
fi

if [[ -z "$PASSWORD" ]]; then
  echo "error: empty password" >&2
  exit 1
fi

if command -v htpasswd >/dev/null 2>&1; then
  # -B bcrypt, -n write to stdout, -b take the password as an argument
  LINE="$(htpasswd -nbB "$USER_NAME" "$PASSWORD")"
elif command -v openssl >/dev/null 2>&1; then
  # openssl has no bcrypt; APR1 is weaker but Traefik accepts it.
  echo "warning: htpasswd not found, falling back to openssl APR1 (weaker than bcrypt)" >&2
  LINE="${USER_NAME}:$(openssl passwd -apr1 "$PASSWORD")"
elif [[ -f "$(dirname "${BASH_SOURCE[0]}")/apr1.py" ]]; then
  # Neither tool is installed on every Falcon host (the trader desk has
  # neither), so fall back to the pure-Python APR1 implementation. Weaker than
  # bcrypt, but it means the operator is never unable to create this file --
  # and a missing file takes the dashboard down, not just its auth.
  echo "warning: htpasswd and openssl not found, using pure-Python APR1 (weaker than bcrypt)" >&2
  LINE="$(python3 "$(dirname "${BASH_SOURCE[0]}")/apr1.py" "$USER_NAME" "$PASSWORD")"
else
  echo "error: need 'htpasswd' (httpd-tools), 'openssl', or scripts/apr1.py" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"
umask 077
printf '%s\n' "$LINE" > "$OUT"
chmod 600 "$OUT"

echo "Wrote ${OUT}"
echo
echo "Next: make it visible to Traefik inside the container, e.g."
echo "  podman volume create falcon-traefik-config   # if it does not exist"
echo "  podman run --rm -v falcon-traefik-config:/dst -v \"\$(dirname "$OUT")\":/src:ro,Z \\"
echo "    alpine cp /src/users.htpasswd /dst/dynamic/users.htpasswd"
echo
echo "Verify Traefik loaded it before trusting the deploy:"
echo "  podman logs falcon-traefik 2>&1 | grep -i 'middleware\\|htpasswd'"
