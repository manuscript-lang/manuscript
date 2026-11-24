// Generator for c64-assembler-extend. The expected outputs come from the Go oracle in
// oracle/*.ref (built with the local Go toolchain). The hidden cases are the inputs of
// c57-assembler-vm (the behavior that must survive the edit) plus scenarios for the new
// instructions and the call-depth limit. Deterministic; run: ms run bench/agent/gen.ms
// -- c64
import (
	JsonValue, parse from "@std/data/json.ms",

	root from "../../core/model.ms",
	Cases, build_oracle, write_cases from "../../lib/gen.ms",
	read_text from "../../lib/text.ms",
)

fn add(var cs Cases, name, script String) Void {
	cs.push(name, script)
}

// The entries of c57-assembler-vm's hidden cases.
fn c57_inputs() List[JsonValue] {
	doc := parse(read_text(f"{root()}/challenges/c57-assembler-vm/hidden/cases.json")).get_or(
		JsonValue.Null
	)
	return doc.as_list() or []
}

export fn gen_c64() Void {
	var cs = Cases(build_oracle("c64-assembler-extend"))

	for entry in c57_inputs() {
		name := (entry.get("name") or JsonValue.Null).as_string() or ""
		stdin := (entry.get("stdin") or JsonValue.Null).as_string() or ""
		add(cs, f"kept-{name}", stdin)
	}

	add(
		cs,
		"minmax-basic",
		"main: mov r0, 5\n mov r1, -3\n min r0, r1\n out r0\n max r1, 10\n out r1\n min r0, 100\n out r0\n max r0, -100\n out r0\n halt\n",
	)
	add(
		cs,
		"minmax-memory",
		".data\nv: .word 7, -9\n.text\nmain: mov r0, 0\n min r0, [v]\n out r0\n max r0, [v+1]\n out r0\n min r0, [5000]\n out r0\n halt\n",
	)
	add(
		cs,
		"minmax-extremes",
		"main: mov r0, 2147483647\n min r0, -2147483648\n out r0\n max r0, 2147483647\n out r0\n min r0, 0x80000000\n out r0\n halt\n",
	)
	add(
		cs,
		"minmax-flags-untouched",
		"main: mov r0, 1\n cmp r0, 5\n min r0, 9\n max r0, 0\n je same\n jl less\n out 0\n halt\nsame: out 1\n halt\nless: out 2\n halt\n",
	)
	add(
		cs,
		"xchg-basic",
		"main: mov r0, 1\n mov r1, 2\n xchg r0, r1\n out r0\n out r1\n xchg r2, r2\n xchg sp, bp\n halt\n",
	)
	add(
		cs,
		"xchg-sort-three",
		"main: in r0\n in r1\n in r2\n mov r3, r0\n min r3, r1\n min r3, r2\n mov r4, r0\n max r4, r1\n max r4, r2\n out r3\n out r4\n halt\n====\n9 -4 17",
	)
	add(
		cs,
		"loop-count",
		"main: mov r0, 5\n mov r1, 0\nagain: add r1, r0\n loop r0, again\n out r1\n out r0\n halt\n",
	)
	add(
		cs,
		"loop-zero-wraps",
		"main: mov r0, 0\n mov r2, 0\nagain: inc r2\n cmp r2, 3\n jge done\n loop r0, again\ndone: out r2\n out r0\n halt\n.budget 50\n",
	)
	add(
		cs,
		"loop-one-iteration",
		"main: mov r0, 1\nagain: out 7\n loop r0, again\n halt\n",
	)
	add(
		cs,
		"loop-flags-untouched",
		"main: mov r0, 2\n cmp r0, 2\nagain: loop r0, again\n je yes\n out 0\n halt\nyes: out 1\n halt\n",
	)
	add(cs, "loop-bad-target", "main: mov r0, 2\n loop r0, 99\n halt\n")
	add(cs, "loop-undefined-label", "main: mov r0, 2\n loop r0, nowhere\n halt\n")
	add(cs, "loop-label-at-end", "main: mov r0, 2\n loop r0, end\n halt\nend:\n")
	add(cs, "new-operand-errors-1", "main: xchg r0, 5\n halt\n")
	add(cs, "new-operand-errors-2", "main: loop 3, main\n halt\n")
	add(cs, "new-operand-errors-3", "main: min [r0], r1\n halt\n")
	add(cs, "new-operand-errors-4", "main: xchg r0\n halt\n")
	add(cs, "new-operand-errors-5", "main: max r0, r1, r2\n halt\n")
	add(cs, "new-operand-errors-6", "main: xchg r0, [r1]\n halt\n")
	add(cs, "new-operand-errors-7", "main: loop r0,\n halt\n")
	add(cs, "new-in-data-section", ".data\n min r0, 1\n.text\nmain: halt\n")
	add(cs, "new-mnemonic-case", "main: MIN r0, 1\n halt\n")
	add(
		cs,
		"call-depth-exact-64",
		"main: mov r0, 64\n call rec\n out 1\n halt\nrec: dec r0\n cmp r0, 0\n jle back\n call rec\nback: ret\n",
	)
	add(
		cs,
		"call-depth-65-traps",
		"main: mov r0, 70\n call rec\n out 1\n halt\nrec: dec r0\n cmp r0, 0\n jle back\n call rec\nback: ret\n",
	)
	add(
		cs,
		"call-depth-after-returns",
		"main: mov r5, 200\nouter: call a\n dec r5\n cmp r5, 0\n jg outer\n out 9\n halt\na: call b\n ret\nb: ret\n",
	)
	add(cs, "call-depth-ret-at-zero", "main: push 5\n ret\n halt\n")
	add(
		cs,
		"call-depth-ret-underflow-mix",
		"main: push 3\n ret\n nop\n call f\n out 4\n halt\nf: ret\n",
	)
	add(cs, "call-depth-vs-stack-overflow", "main: mov sp, 0\n call f\n halt\nf: ret\n")
	add(
		cs,
		"call-depth-trap-before-stack-overflow",
		"main: mov r0, 0\nloop1: call deeper\n halt\ndeeper: inc r0\n cmp r0, 64\n jge stackout\n call deeper\n ret\nstackout: mov sp, 0\n call f\n halt\nf: ret\n",
	)
	add(
		cs,
		"call-depth-with-ret-jump",
		"main: call f\n out 1\n halt\nf: pop r0\n jmp r0\n",
	)
	add(
		cs,
		"loop-and-calls",
		"main: mov r0, 70\nagain: call f\n loop r0, again\n out r0\n halt\nf: mov r1, 3\n xchg r1, r2\n ret\n",
	)

	examples := [
		cs.make(
			"ex-minmax-loop",
			"main: mov r0, 4\n mov r1, 0\nagain: max r1, r0\n loop r0, again\n out r1\n min r1, 2\n out r1\n halt\n",
		),
		cs.make(
			"ex-call-depth",
			"main: mov r0, 70\n call rec\n halt\nrec: dec r0\n cmp r0, 0\n jle back\n call rec\nback: ret\n",
		),
	]
	write_cases("c64-assembler-extend", examples, cs.list)
}
