// ms: effect db.write
// ms: allow_effect std.console.write
fn exec(sql: String) Void:
    print(sql)

// ms: allow_effect db.*
fn save(o: String) Void:
    exec(o)

fn bad(o: String) Void:
    exec(o)

// ms: allow_effect db.*
fn leaky(o: String) Void:
    print(o)

fn main() Void:
    return
