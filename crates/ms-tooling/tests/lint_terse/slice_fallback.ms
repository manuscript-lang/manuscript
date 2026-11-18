fn main() Void:
    xs := [1, 2, 3]
    print(xs.slice(0, 9).get_or([]).length())
    print(xs.slice(0, 2).get_or([]).length())
