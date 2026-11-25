// ms: allow_effect std.console.write

// Reports build prerequisites without downloading or changing the checkout
// (`make doctor`). Usage: ms run tools/doctor.ms
import (
	stdout from "@std/io/io.ms",
	read_file from "@std/os/fs.ms",

	capture, env, host, works from "./lib.ms",
)

fn say(ok Bool, ok_text, missing_text String) Bool {
	if ok {
		print(f"OK      {ok_text}")
	} else {
		print(f"MISSING {missing_text}")
	}

	return ok
}

// Whether `version` ("0.146.7") is at least 0.146.7.
// Whether `hugo version` output names an extended build new enough for the book.
fn hugo_usable(output String) Bool {
	fields := output.split(" ").collect()
	return (
		output.contains("extended")
		and fields.length() > 1
		and hugo_new_enough(fields[1].replace("v", ""))
	)
}

fn hugo_new_enough(version String) Bool {
	parts := (
		version
		.split("-")
		.collect()[0]
		.split("+")
		.collect()[0]
		.split(".")
		.collect()
	)
	if parts.length() < 3 { return false }

	major := parts[0].parse_int() or 0
	minor := parts[1].parse_int() or 0
	patch := parts[2].parse_int() or 0
	return major > 0 or minor > 146 or (minor == 146 and patch >= 7)
}

fn main() Int {
	var failed = 0
	for command in ["git", "tar"] {
		if not say(works(command, ["--version"]), command, command) { failed += 1 }
	}

	expected_node := (
		read_file(".node-version").wait().get().decode_utf8()
		or "".trim()
	)
	node := capture("node", ["--version"]).trim()
	if not say(
		node == f"v{expected_node}",
		f"Node {expected_node}",
		f"Node {expected_node} (install the version in .node-version)",
	) { failed += 1 }
	for command in ["cmake", "ninja"] {
		if not say(
			works(command, ["--version"]),
			command,
			f"{command} (builds ms: cmake --preset ci)",
		) { failed += 1 }
	}
	if not say(
		works("clang", ["--version"]),
		"clang",
		"clang (the C compiler the ci preset builds with)",
	) { failed += 1 }
	if not say(
		works("python3", ["--version"]) or works("python", ["--version"]),
		"Python 3 (debugger helper tests)",
		"Python 3 (needed by the debugger helper tests in tools/debugger)",
	) { failed += 1 }

	hugo := env("HUGO", "hugo")
	hugo_output := capture(hugo, ["version"])

	if hugo_usable(hugo_output) {
		void stdout().write(hugo_output).get()
	} else {
		print("MISSING Hugo Extended 0.146.7 or newer (book checks)")
		failed += 1
	}

	if host() == "windows" {
		if not say(works("7z", ["i"]), "7z (packaging)", "7z (packaging)") { failed += 1 }
	} else {
		if not say(
			works("cc", ["--version"]),
			"C compiler (building ms from source; running ms needs none on Linux)",
			"C compiler (building ms from source: ring)",
		) { failed += 1 }
	}

	if failed > 0 { return 1 }

	return 0
}
