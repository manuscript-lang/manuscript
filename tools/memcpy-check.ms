// Emitted-copy budget (`make memcpy-check`): `ms emit --opt --ir` prints the LLVM IR
// the back end receives, where every
// `llvm.memcpy` and `llvm.memmove` is a block of bytes the generated code moves between two cells. A value has one owner and
// moves, so each is a real move (a record into an optional, a result into the caller's
// area) and none is a hidden copy. tools/memcpy-budget.txt lists, per benchmark
// program, how many the compiler may emit; the check fails when a program emits more,
// so a change that adds copies must say why and raise the budget. Usage: ms run
// tools/memcpy-check.ms
import (
	change_directory, working_directory from "@std/os/env.ms",
	read_file from "@std/os/fs.ms",
	RunOptions, run from "@std/os/process.ms",
	seconds from "@std/time.ms",

	tool_ms from "./lib.ms",
)

// The copies in one module of IR text.
fn copies(ir String) Int {
	var count = 0
	for line in ir.split("\n") {
		if (
			line.starts_with("  call void @llvm.memcpy.")
			or line.starts_with("  call void @llvm.memmove.")
		) {
			count += 1
		}
	}
	return count
}

fn main() Int {
	root := working_directory().get()
	ms := tool_ms(root.clone())
	budget := (
		read_file(f"{root}/tools/memcpy-budget.txt").wait().get().decode_utf8()
		or ""
	)
	var failing = 0
	var checked = 0

	for line in budget.split("\n") {
		if line.is_empty() or line.starts_with(
			"#"
		) { continue }

		columns := line.split("\t").collect()
		allowed := columns[0].parse_int() or 0
		program := columns[1].clone()
		out := run(
			ms.clone(),
			["emit", f"{root}/{program}", "--opt", "--ir"],
			RunOptions(timeout: seconds(120)),
		).wait().get()
		found := copies(out.stdout.decode_utf8() or "")
		checked += 1

		if found > allowed {
			failing += 1
			print(f"{program}: {found} copies, budget {allowed}")
		} else if found < allowed {
			print(f"{program}: {found} copies, budget {allowed}; lower the budget")
		}
	}

	if checked == 0 {
		print("no program was checked")
		return 1
	}

	print(f"checked {checked} programs, {failing} over budget")
	void change_directory(root).get()
	if failing != 0 { return 1 }

	return 0
}
