import arguments from "@std/os/env.ms"

fn main() Unit:
    print("Arguments: {arguments().length()}")
