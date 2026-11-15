type Hook:
    run: fn() Int

export fn main() Int:
    items: List[Int] := [1]
    hook := Hook(fn: items.length())
    print(f"{items.length()}")
    return hook.run()
