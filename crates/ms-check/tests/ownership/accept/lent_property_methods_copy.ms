type Name:
    text: String

fn keep(move name: Name) Int:
    return name.text.length()

fn Name.to_string() String:
    return f"{keep(self.clone())}"

fn Name.hash() Int:
    return keep(self.clone())
