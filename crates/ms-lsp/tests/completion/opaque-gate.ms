export opaque type Tok:
    id: Int

fn Tok.show() String:
    return f"{self.id}"

export fn mk() Tok:
    return Tok(id: 1)
