export enum Choice[T]:
    Value(value: T)
    Empty

enum Other:
    Value(value: Int)
    Empty

fn bare(input: Choice[Int]) Int:
    match input:
        Value(n): return n
        Empty: return 0

fn qualified(input: Choice[Int]) Int:
    match input:
        Choice[Int].Value(n): return n
        Choice.Empty: return 0

fn other(input: Other) Int:
    match input:
        Other.Value(n): return n
        Other.Empty: return 0

export fn calls() Int:
    return bare(Choice[Int].Value(1)) + qualified(Choice[Int].Empty) + other(Other.Value(2))
