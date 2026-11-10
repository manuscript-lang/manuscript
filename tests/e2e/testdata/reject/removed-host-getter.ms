export fn main() Int:
    host := filesystem()
    return host.read_file("a.txt").length()
