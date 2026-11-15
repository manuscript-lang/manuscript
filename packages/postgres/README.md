# postgres

A PostgreSQL client written in Manuscript over the standard library's TCP and TLS. No C and no Rust crates.

Supported: protocol v3 startup, SCRAM-SHA-256 login (the server must prove it knows the password), the simple and
extended query protocols (parse, bind and execute in one round trip), prepared statements, typed parameters and results
in text format, transactions, server errors that carry their SQLSTATE in `Error.kind`, and a pool of worker tasks.

## Logins

Only SCRAM-SHA-256 is accepted by default. A cleartext password is sent only over TLS. An md5 challenge is refused
unless `Config.allow_md5` is true.

## TLS

TLS needs PostgreSQL 17 or later. The stdlib can only start TLS on a fresh connection, so the client uses direct TLS
(ALPN `postgresql`) and not the SSLRequest upgrade that older servers need. Older servers work once the stdlib can
upgrade an open connection ([#4011](https://github.com/manuscript-lang/manuscript/issues/4011)). Direct TLS has not
been run against a server here; no PostgreSQL 17 was available.

## Use

```manuscript
import Config, open from "@pg/conn.ms"
import Value from "@pg/value.ms"

fn main() Unit!:
    var conn = open(Config(password: "secret"))?
    rows := conn.query("select $1::int8 + 1", [Value.Int(41)])?
    print("{rows.rows[0][0]}")
    conn.close()?
    return ok(unit)
```

`Pool` (`@pg/pool.ms`) runs statements on worker tasks that each own one connection. A connection cannot move
between tasks, so statements travel to the workers over pipes and rows travel back; one task owns the `Pool`.

## Tests

`eval $(tests/start-postgres.sh /tmp/pg)` starts a throwaway server with the roles the tests need, then `ms test`.
Settings come from `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` and `PGDATABASE`. CI runs them nightly on Linux,
macOS and Windows.
