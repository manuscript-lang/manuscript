#!/usr/bin/env bash
# Starts a throwaway PostgreSQL server for the tests and prints the PG* variables to export.
# Needs initdb and pg_ctl on PATH (or PG_BIN); runs as a non-root user. Works on Linux, macOS and Windows (Git Bash).
set -euo pipefail
dir="${1:-$(mktemp -d)}"
port="${PGPORT:-5433}"
bin="${PG_BIN:-}"
[ -n "$bin" ] && export PATH="$bin:$PATH"
printf 'secret' > "$dir/pw"
initdb -D "$dir/data" -A scram-sha-256 --pwfile="$dir/pw" -U postgres > /dev/null
pg_ctl -D "$dir/data" -o "-p $port -c listen_addresses=127.0.0.1" -l "$dir/log" -w start > /dev/null
echo "PGPORT=$port PGPASSWORD=secret PGUSER=postgres PGHOST=127.0.0.1"
