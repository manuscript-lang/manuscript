import arguments from "@std/os/env.ms"

export fn main() Int:
    print("Arguments: {arguments().length()}")
    return 0
