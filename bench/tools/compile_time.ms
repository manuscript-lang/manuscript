# Generates the same program in Manuscript and Go and times each build.
# Usage: ms run bench/tools/compile_time.ms [-- packages files fns]   (default 40 25 10, about 122k lines of Manuscript)
# OUT keeps the generated sources; MS picks the compiler; SKIP_LLVM=1 skips the release build.
# Generated Manuscript and Go source contains many braces; `q` writes them as ‹ and › so the generator reads as source.
import absolute, env, fail, ms_binary, must, now_ns, run_in, usage, write_text from "./lib.ms"
import create_directory, remove, temporary from "@std/os/fs.ms"
import arguments, set_environment from "@std/os/process.ms"
import SeededRandom, seeded from "@std/os/random.ms"
import stdout from "@std/io/io.ms"

fn q(text: String) String:
    return text.replace("‹", "\{").replace("›", "\}")

# Whether the next draw picks a nearby dependency (70% of draws).
fn chance(var rng: SeededRandom) Bool:
    return rng.int(0, 100) < 70

type Dep:
    pkg: Int
    file: Int

fn deps(var rng: SeededRandom, files: Int, p: Int, f: Int) List[Dep]:
    let i = p * files + f
    var found = List[Dep]()

    for _n in 0..3:
        if i == 0: break

        let low = if chance(var rng): (if i - 60 > 0: i - 60 else: 0) else: 0

        let j = low + rng.int(0, i - low)
        let d = Dep(j / files, j % files)
        if not found.any(fn e: e.pkg == d.pkg and e.file == d.file): found.append(d)

    return found.sorted(
        fn(a: Dep, b: Dep) Int: if a.pkg != b.pkg: a.pkg - b.pkg else: a.file - b.file
    )

fn call_of(prefix: String, d: List[Dep], k: Int, own: Int, qualified: Bool) String:
    if d.length() == 0: return "0"

    let dep = d[k % d.length()]

    let pk = if qualified and dep.pkg != own: "p{dep.pkg}." else: ""

    return "{pk}{prefix}_{dep.pkg}_{dep.file}_0(acc % 1000)"

fn ms_fn(p: Int, f: Int, k: Int, d: List[Dep]) String:
    let call = call_of("w", d, k, p, false)
    let shape = k % 4
    var b = ["export fn w_{p}_{f}_{k}(x: Int) Int:"]

    if shape == 0:
        b = b.concat(
            [
                "    var acc = x", "    for i in 0..10:", "        if i % 2 == 0:",
                "            acc += i * 3", "        else:", "            acc -= 1",
                "    return acc % 100000 + {call}"
            ]
        )
    else if shape == 1:
        b = b.concat(
            [
                "    var xs = List[Int]()", "    for i in 0..8:",
                "        xs.append(i + x)", "    var t = 0", "    for v in xs:",
                "        t += v % 7", "    let acc = t + xs.length()",
                "    return acc + {call}"
            ]
        )
    else if shape == 2:
        b = b.concat(
            [
                q("    let r = R_{p}_{f}(x, \"n‹x›\", [x, 1, 2])"),
                "    var acc = r.score()", "    while acc > 1000:",
                "        acc = acc / 2", "    return acc + {call}"
            ]
        )
    else:
        b = b.concat(
            [
                q("    let s = \"v‹x›\""), "    var acc = s.length()", "    if x > 50:",
                "        acc += x / 3", "    else if x > 10:", "        acc += x * 2",
                "    else:", "        acc += 1", "    return acc + {call}"
            ]
        )

    return b.join("\n") + "\n"

fn go_fn(p: Int, f: Int, k: Int, d: List[Dep]) String:
    let call = call_of("W", d, k, p, true)
    let shape = k % 4
    var b = [q("func W_{p}_{f}_{k}(x int) int ‹")]

    if shape == 0:
        b = b.concat(
            [
                "\tacc := x", q("\tfor i := 0; i < 10; i++ ‹"), q("\t\tif i%2 == 0 ‹"),
                "\t\t\tacc += i * 3", q("\t\t› else ‹"), "\t\t\tacc -= 1", "\t\t›",
                "\t›", "\treturn acc%100000 + {call}"
            ]
        )
    else if shape == 1:
        b = b.concat(
            [
                "\txs := []int" + q("‹›"), q("\tfor i := 0; i < 8; i++ ‹"),
                "\t\txs = append(xs, i+x)", "\t›", "\tt := 0",
                q("\tfor _, v := range xs ‹"), "\t\tt += v % 7", "\t›",
                "\tacc := t + len(xs)", "\treturn acc + {call}"
            ]
        )
    else if shape == 2:
        b = b.concat(
            [
                q(
                    "\tr := R_{p}_{f}‹x, fmt.Sprintf(\"n%d\", x), []int‹x, 1, 2››"
                ),
                "\tacc := r.Score()",
                q("\tfor acc > 1000 ‹"),
                "\t\tacc = acc / 2",
                "\t›",
                "\treturn acc + {call}"
            ]
        )
    else:
        b = b.concat(
            [
                "\ts := fmt.Sprintf(\"v%d\", x)", "\tacc := len(s)", q("\tif x > 50 ‹"),
                "\t\tacc += x / 3", q("\t› else if x > 10 ‹"), "\t\tacc += x * 2",
                q("\t› else ‹"), "\t\tacc += 1", "\t›", "\treturn acc + {call}"
            ]
        )

    b.append("›")
    return q(b.join("\n")) + "\n"

fn generate(out: String, packages: Int, files: Int, fns: Int) Unit:
    var rng = seeded(1)
    create_directory("{out}/ms/src", recursive: true).get()
    create_directory("{out}/go", recursive: true).get()
    write_text("{out}/go/go.mod", "module bigprog\n\ngo 1.21\n")

    for p in 0..packages:
        create_directory("{out}/ms/src/pkg{p}", recursive: true).get()
        create_directory("{out}/go/p{p}", recursive: true).get()

        for f in 0..files:
            let d = deps(var rng, files, p, f)
            var m = List[String]()

            for dep in d:
                let path = if dep.pkg == p: "./f{dep.file}.ms" else: "../pkg{dep.pkg}/f{dep.file}.ms"

                m.append("import w_{dep.pkg}_{dep.file}_0 from \"{path}\"\n")

            m.append(
                "\nexport type R_{p}_{f}:\n    a: Int\n    b: String\n    c: List[Int]\n\nimpl R_{p}_{f}:\n    fn score() Int:\n        var t = self.a + self.b.length()\n        for v in self.c:\n            t += v\n        return t\n\n"
            )
            for k in 0..fns:
                m.append(ms_fn(p, f, k, d) + "\n")
            m.append("export fn all_{p}_{f}(x: Int) Int:\n    var t = 0\n")
            for k in 0..fns:
                m.append("    t += w_{p}_{f}_{k}(x)\n")
            m.append("    return t % 100000\n")
            write_text("{out}/ms/src/pkg{p}/f{f}.ms", m.join(""))

            var g = ["package p{p}\n\nimport \"fmt\"\n"]
            var other = Set[Int]()
            for dep in d:
                if dep.pkg != p: other.add(dep.pkg)
            for dpk in other.values().sorted():
                g.append("import \"bigprog/p{dpk}\"\n")
            g.append(
                q(
                    "\nvar _ = fmt.Sprint\n\ntype R_{p}_{f} struct ‹\n\tA int\n\tB string\n\tC []int\n›\n\nfunc (r R_{p}_{f}) Score() int ‹\n\tt := r.A + len(r.B)\n\tfor _, v := range r.C ‹\n\t\tt += v\n\t›\n\treturn t\n›\n\n"
                )
            )
            for k in 0..fns:
                g.append(go_fn(p, f, k, d) + "\n")
            g.append(q("func All_{p}_{f}(x int) int ‹\n\tt := 0\n"))
            for k in 0..fns:
                g.append("\tt += W_{p}_{f}_{k}(x)\n")
            g.append(q("\treturn t % 100000\n›\n"))
            write_text("{out}/go/p{p}/f{f}.go", g.join(""))

    var ms = ["import stdout from \"@std/io/io.ms\"\n"]
    for p in 0..packages:
        for f in 0..files:
            ms.append("import all_{p}_{f} from \"./pkg{p}/f{f}.ms\"\n")
    ms.append("\nexport fn main() Int:\n    var t = 0\n")
    for p in 0..packages:
        for f in 0..files:
            ms.append("    t += all_{p}_{f}(7)\n")
    ms.append(q("    stdout().write(\"‹t›\\n\").get()\n    return 0\n"))
    write_text("{out}/ms/src/main.ms", ms.join(""))
    write_text(
        "{out}/ms/ms.toml",
        "[project]\nname = \"big\"\nsource = \"./src\"\nentry = \"./src/main.ms\"\n"
    )

    var go = ["package main\n\nimport \"fmt\"\n"]
    for p in 0..packages:
        go.append("import \"bigprog/p{p}\"\n")
    go.append(q("\nfunc main() ‹\n\tt := 0\n"))
    for p in 0..packages:
        for f in 0..files:
            go.append("\tt += p{p}.All_{p}_{f}(7)\n")
    go.append("\tfmt.Println(t)\n" + q("›\n"))
    write_text("{out}/go/main.go", go.join(""))

# Runs a build and prints its label with the elapsed seconds.
fn timed(
    label: String,
    dir: String,
    program: String,
    args: List[String]
) Result[Unit, Error]:
    let start = now_ns()
    let _ = try must(label, run_in(dir, program, args))
    let seconds = (now_ns() - start).to_float() / 1000000000.0
    stdout().write("{label} {seconds.to_fixed(2)} s\n").get()
    return ok(unit)

fn drop_cache(dir: String) Unit:
    remove("{dir}/.ms-cache", recursive: true).get(unit)

fn run(out: String, p: Int, f: Int, k: Int) Result[Unit, Error]:
    generate(out, p, f, k)

    let ms = ms_binary()
    let go = env("GO", "go")
    let _ = try must("go clean", run_in("{out}/go", go, ["clean", "-cache"]))
    try timed("go cold:  ", "{out}/go", go, ["build", "-o", "../gobin", "."])
    try timed("ms check: ", "{out}/ms", ms, ["check", "ms.toml"])
    try timed("ms emit:  ", "{out}/ms", ms, ["emit", "ms.toml"])
    drop_cache("{out}/ms")
    try timed(
        "ms debug: ", "{out}/ms", ms,
        ["build", "ms.toml", "-o", "../msbin_d", "--build-type", "Debug"]
    )
    drop_cache("{out}/ms")
    set_environment("MS_BACKEND", "cranelift").get()
    try timed("ms clif:  ", "{out}/ms", ms, ["build", "ms.toml", "-o", "../msbin_c"])
    set_environment("MS_BACKEND", none).get()

    if env("SKIP_LLVM", "") == "":
        drop_cache("{out}/ms")
        try timed("ms release:", "{out}/ms", ms, ["build", "ms.toml", "-o", "../msbin"])

    return ok(unit)

export fn main() Int:
    let args = arguments()
    var dims = [40, 25, 10]

    for i in 0..3:
        if args.length() > i:
            let v = args[i].parse_int().get(0)
            if v < 1: return usage("packages, files and fns must be positive integers")

            dims[i] = v

    let keep = env("OUT", "")
    var out = ""

    if keep != "":
        out = absolute(keep)
        remove(out, recursive: true).get(unit)
    else:
        out = temporary("compile-time-").get().path()

    let result = run(out, dims[0], dims[1], dims[2])
    if result.is_error(): return fail(result.err().message())

    return 0
