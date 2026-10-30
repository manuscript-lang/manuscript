type View:
    items: ref List[Int]

fn f(xs: List[Int]) Int:
    let v = View(items: xs)
    var fs: List[fn() Int] = []
    fs.append(fn (): v.items.length())  # error: captures `v`
    return v.items.length() + fs.length()
