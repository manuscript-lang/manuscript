import open from "@std/os/fs.ms"

fn first_line(path String) String! {
	file := open(path)?
	lines := file.read_lines(max_lines: 100)?
	return ok(lines[0].clone())
}

fn main() Void {
	print(first_line("scope.ms").get_or("unreadable"))
}
