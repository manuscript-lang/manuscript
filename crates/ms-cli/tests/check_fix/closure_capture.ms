type Hook:
    run: fn() Int

export fn main() Int:
    let items: List[Int] = [1]
    let hook = Hook(fn: items.length())
    print("{items.length()}")
    return hook.run()
