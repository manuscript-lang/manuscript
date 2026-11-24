// conform: tags=ownership,tier-core
// conform: phase=check
// A list literal makes a new owner of each element, so a borrowed element needs `.clone()`.
fn pair(name: String) List[String]:
    return [name]

fn main() Void:
    print(pair("a").length())
