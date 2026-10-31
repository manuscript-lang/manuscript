import basename from "@std/fs.ms"

export fn main() Int:
    return basename("reports/today.txt").length()
