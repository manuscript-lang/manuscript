export fn main() Int:
    let host = filesystem()
    return host.read_file("a.txt").length()
