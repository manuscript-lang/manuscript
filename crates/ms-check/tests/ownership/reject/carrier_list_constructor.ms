type View:
    s: ref String
    n: Int

fn f() Int:
    var views = List[View]()  # error: a collection cannot do
    return views.length()
