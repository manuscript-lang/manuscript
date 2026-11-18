type Name:
    text: String

fn keep(move name: Name) Int:
    return name.text.length()

fn Name.to_string() String:  // error: `to_string` keeps `self`, but the language calls it when it shows a value as text
    return f"{keep(self)}"

fn Name.equals(other: Name) Bool:  // error: `equals` keeps `other`, but the language calls it when it compares values with `==`
    return keep(other) == self.text.length()

fn Name.hash() Int:  // error: `hash` keeps `self`, but the language calls it when it hashes a value
    return keep(self)

fn Name.compare(other: Name) Int:  // error: `compare` keeps `other`, but the language calls it when it orders values
    return keep(other) - self.text.length()
