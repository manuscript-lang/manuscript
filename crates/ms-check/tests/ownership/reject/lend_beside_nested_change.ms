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
    return "{a}{b}"

fn wrap(s: String) String:
    return s

fn demo(var r: Row) Int:
    let a = two(label(r), mutate(var r))  # error: argument `mutate(..)` of `two` is changed in place but overlaps argument `label(..)`; a changed value cannot also be read or changed through another operand, so pass distinct variables or copy one first
    let b = two(label(r), wrap(mutate(var r)))  # error: argument `wrap(..)` of `two` is changed in place but overlaps argument `label(..)`; a changed value cannot also be read or changed through another operand, so pass distinct variables or copy one first
    let c = label(r) + mutate(var r)  # error: operand `mutate(..)` of `+` is changed in place but overlaps operand `label(..)`; a changed value cannot also be read or changed through another operand, so pass distinct variables or copy one first
    let d = items_of(r)[idx(var r)].length()  # error: operand `idx(..)` of this index is changed in place but overlaps operand `items_of(..)`; a changed value cannot also be read or changed through another operand, so pass distinct variables or copy one first
    let e = "{label(r)} {mutate(var r)}"  # error: operand `mutate(..)` of this text is changed in place but overlaps operand `label(..)`; a changed value cannot also be read or changed through another operand, so pass distinct variables or copy one first
    return a.length() + b.length() + c.length() + d + e.length()
