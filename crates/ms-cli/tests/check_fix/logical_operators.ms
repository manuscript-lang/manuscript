fn both(left: Bool, right: Bool) Bool:
    return left&&right

fn either(left: Bool, right: Bool) Bool:
    return left||right

export fn main() Int:
    return if both(true, false) or either(true, false): 0 else: 1
