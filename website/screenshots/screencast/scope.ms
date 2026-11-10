import open from "@std/os/fs.ms"

fn first_line(path: String) String!:
    file := try open(path)
    lines := try file.read_lines(max_lines: 100)
    return ok(lines[0].clone())

fn main() Unit:
    print(first_line("scope.ms").get("unreadable"))
