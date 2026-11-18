type Pet:
    name: String

interface Label:
    fn text() String

fn Pet.text() String:
    return self.name

fn show(l: Label) String:
    return l.text()

fn f() String:
    return show(Pet("rex"))  // error: returns a part of its receiver
