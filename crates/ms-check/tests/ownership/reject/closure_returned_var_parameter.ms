type Rec:
    items: List[String]

type Keeper:
    f: fn() Int

fn var Rec.holder() fn() Int:
    return fn: self.items.length()  // error: captures the `var` receiver `self`

fn hold(var r: Rec) fn() Int:
    return fn: r.items.length()  // error: captures the `var` parameter `r`

fn keep(var r: Rec) Keeper:
    return Keeper(fn: r.items.length())  // error: captures the `var` parameter `r`

fn push(var r: Rec, var fs: List[fn() Int]) Void:
    fs.append(fn: r.items.length())  // error: captures the `var` parameter `r`
