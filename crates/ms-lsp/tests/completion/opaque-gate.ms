export opaque type Tok:
    id: Int

impl Tok:
    fn show() String:
        return "{self.id}"

export fn mk() Tok:
    return Tok(id: 1)
