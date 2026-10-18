import panic from "@std/faults.ms"

export fn main() Int:
    return panic("check must not execute main")
