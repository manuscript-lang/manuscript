type Row:
    name: String
    tags: List[String]

fn label(r: Row) String:
    return r.name

fn items_of(r: Row) List[String]:
    return r.tags

fn mutate(var r: Row) String:
    r.name = "changed"
    return "m"

fn idx(var r: Row) Int:
    r.tags = []
    return 0

fn two(a: String, b: String) String:
    return f"{a}{b}"

fn wrap(s: String) String:
    return s

fn demo(var r: Row) Int:
    a := two(label(r), mutate(r))  // error: argument `mutate(..)` of `two` is moved or changed in place but overlaps argument `label(..)`; a moved or changed value cannot also be read or changed through another operand, so pass distinct variables or clone one first
    b := two(label(r), wrap(mutate(r)))  // error: argument `wrap(..)` of `two` is moved or changed in place but overlaps argument `label(..)`; a moved or changed value cannot also be read or changed through another operand, so pass distinct variables or clone one first
    c := label(r) + mutate(r)  // error: operand `mutate(..)` of `+` is moved or changed in place but overlaps operand `label(..)`; a moved or changed value cannot also be read or changed through another operand, so pass distinct variables or clone one first
    d := items_of(r)[idx(r)].length()  // error: operand `idx(..)` of this index is moved or changed in place but overlaps operand `items_of(..)`; a moved or changed value cannot also be read or changed through another operand, so pass distinct variables or clone one first
    e := f"{label(r)} {mutate(r)}"  // error: operand `mutate(..)` of this text is moved or changed in place but overlaps operand `label(..)`; a moved or changed value cannot also be read or changed through another operand, so pass distinct variables or clone one first
    return a.length() + b.length() + c.length() + d + e.length()
