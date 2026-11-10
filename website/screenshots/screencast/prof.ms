fn fib(n: Int) Int:
    if n < 2: return n

    return fib(n - 1) + fib(n - 2)

export fn main() Int:
    print(fib(38))
    return 0
