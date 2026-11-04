import files from "@assets"

export fn main() Int:
    let tree = files()
    if tree.read("program.ms-build.json", none).is_ok():
        return 7
    return 1
