// ms: effect db.write
// ms: allow_effect std.console.write
fn exec(sql: String) Unit:
    print(sql)

// ms: allow_effect db.*
fn save(o: String) Unit:
    exec(o)

fn bad(o: String) Unit:
    exec(o)

// ms: allow_effect db.*
fn leaky(o: String) Unit:
    print(o)

export fn main() Int:
    return 0
