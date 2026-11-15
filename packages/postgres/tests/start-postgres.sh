#!/usr/bin/env bash
# Starts a throwaway PostgreSQL server for the tests and prints the PG* variables to export.
# Needs initdb and pg_ctl on PATH (or PG_BIN); runs as a non-root user. Works on Linux, macOS and Windows (Git Bash).
set -euo pipefail
dir="${1:-$(mktemp -d)}"
port="${PGPORT:-5433}"
bin="${PG_BIN:-}"
sockets="-c unix_socket_directories=$dir"
if command -v cygpath > /dev/null; then
  # Git Bash on Windows: native PostgreSQL wants Windows paths, has no Unix sockets, and PATH uses `/c/...`.
  dir=$(cygpath -m "$dir")
  [ -n "$bin" ] && bin=$(cygpath -u "$bin")
  sockets=""
fi
[ -n "$bin" ] && export PATH="$bin:$PATH"
mkdir -p "$dir"
printf 'secret' > "$dir/pw"
initdb -D "$dir/data" -A scram-sha-256 --pwfile="$dir/pw" -U postgres > /dev/null
# Roles that log in by md5 and by cleartext password, to test that the client refuses them by default.
{ echo "host all md5user 127.0.0.1/32 md5"; echo "host all clearuser 127.0.0.1/32 password"; cat "$dir/data/pg_hba.conf"; } > "$dir/hba"
mv "$dir/hba" "$dir/data/pg_hba.conf"
# A self-signed certificate for localhost, so the tests can run the SSLRequest upgrade.
cat > "$dir/cert.cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = localhost
[ext]
subjectAltName = DNS:localhost,IP:127.0.0.1
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -config "$dir/cert.cnf" -keyout "$dir/data/server.key" -out "$dir/data/server.crt" 2> /dev/null
chmod 600 "$dir/data/server.key"
pg_ctl -D "$dir/data" -o "-p $port -c listen_addresses=127.0.0.1 $sockets -c ssl=on" -l "$dir/log" -w start > /dev/null
export PGPASSWORD=secret
psql -h 127.0.0.1 -p "$port" -U postgres -q -c "SET password_encryption='md5'; CREATE ROLE md5user LOGIN PASSWORD 'md5pass';" -c "SET password_encryption='scram-sha-256'; CREATE ROLE clearuser LOGIN PASSWORD 'clearpass';" > /dev/null
echo "PGSSLROOTCERT=$dir/data/server.crt PGPORT=$port PGPASSWORD=secret PGUSER=postgres PGHOST=127.0.0.1"
