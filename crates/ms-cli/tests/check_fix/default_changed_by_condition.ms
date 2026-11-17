fn bump(var n: Int) Bool:
    n += 1
    return false

export fn main() Void:
    var a = 1
    var y = a
    if bump(var a):
        y = 5
    print(f"{y} {a}")
