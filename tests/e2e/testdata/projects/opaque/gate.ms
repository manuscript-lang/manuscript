export opaque type Approved:
    entity: String
    nonce: String

export opaque type Counter:
    count: Int

export opaque type Mode:
    case Safe
    case Wild(level: Int)

impl Approved:
    fn label() String:
        return "approved:{self.entity}"

impl Counter:
    var fn bump() Unit:
        self.count += 1

    fn value() Int:
        return self.count

export fn approve(entity: String) Approved:
    return Approved(entity: entity, nonce: "n1")

export fn entity(a: Approved) String:
    return a.entity.clone()

export fn counter() Counter:
    return Counter(count: 0)

export fn safe() Mode:
    return Safe

export fn wild(level: Int) Mode:
    return Wild(level)

export fn level(m: Mode) Int:
    match m:
        Safe: return 0
        Wild(level): return level

export fn nonce_of(a: Approved) String:
    return a.nonce.clone()
