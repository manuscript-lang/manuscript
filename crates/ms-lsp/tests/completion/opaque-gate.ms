export opaque type Tok:
    id: Int

fn Tok.show() String:
    return "{self.id}"

export fn mk() Tok:
    return Tok(id: 1)
