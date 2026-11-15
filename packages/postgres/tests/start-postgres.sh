#!/usr/bin/env bash
# Starts a throwaway PostgreSQL server for the tests and prints the PG* variables to export.
# Needs initdb and pg_ctl on PATH (or PG_BIN); runs as a non-root user. Works on Linux, macOS and Windows (Git Bash).
set -euo pipefail
dir="${1:-$(mktemp -d)}"
port="${PGPORT:-5433}"
bin="${PG_BIN:-}"
[ -n "$bin" ] && export PATH="$bin:$PATH"
mkdir -p "$dir"
printf 'secret' > "$dir/pw"
initdb -D "$dir/data" -A scram-sha-256 --pwfile="$dir/pw" -U postgres > /dev/null
# Roles that log in by md5 and by cleartext password, to test that the client refuses them by default.
{ echo "host all md5user 127.0.0.1/32 md5"; echo "host all clearuser 127.0.0.1/32 password"; cat "$dir/data/pg_hba.conf"; } > "$dir/hba"
mv "$dir/hba" "$dir/data/pg_hba.conf"
pg_ctl -D "$dir/data" -o "-p $port -c listen_addresses=127.0.0.1 -c unix_socket_directories=$dir" -l "$dir/log" -w start > /dev/null
export PGPASSWORD=secret
psql -h 127.0.0.1 -p "$port" -U postgres -q -c "SET password_encryption='md5'; CREATE ROLE md5user LOGIN PASSWORD 'md5pass';" -c "SET password_encryption='scram-sha-256'; CREATE ROLE clearuser LOGIN PASSWORD 'clearpass';" > /dev/null
echo "PGPORT=$port PGPASSWORD=secret PGUSER=postgres PGHOST=127.0.0.1"
