# postgres

A PostgreSQL client written in Manuscript over the standard library's TCP and TLS. No C and no Rust crates.

Supported today: protocol v3 startup, cleartext, md5 and SCRAM-SHA-256 authentication, the simple and the extended
(parse, bind, execute in one round trip) query protocols, typed parameters and results, transactions, and server errors
carrying their SQLSTATE in `Error.kind`.

```manuscript
import Config, open from "./conn.ms"
import Value from "./value.ms"

fn main() Unit!:
    var conn = open(Config(password: "secret"))?
    rows := conn.query("select $1::int8 + 1", [Value.Int(41)])?
    print("{rows.rows[0][0]}")
    conn.close()?
    return ok(unit)
```

Tests need a server: `eval $(tests/start-postgres.sh /tmp/pg)` then `ms test tests/postgres.ms`.
Connection settings come from `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` and `PGDATABASE`.
