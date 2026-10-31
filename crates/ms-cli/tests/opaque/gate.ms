import JsonValue from "@std/json.ms"

export opaque type Approved:
    entity: String
    nonce: String

export opaque type Mode:
    case Safe
    case Wild(level: Int)

export fn approve(entity: String) Approved:
    return Approved(entity: entity, nonce: "n1")

export fn entity(a: Approved) String:
    return a.entity.clone()

export fn safe() Mode:
    return Safe

export fn wild(level: Int) Mode:
    return Wild(level)

export fn level(m: Mode) Int:
    match m:
        Safe: return 0
        Wild(level): return level

impl Approved:
    fn label() String:
        return "approved:{self.entity}"
