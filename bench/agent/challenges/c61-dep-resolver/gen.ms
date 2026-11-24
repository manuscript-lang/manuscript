// Generator for c61-dep-resolver. The expected outputs come from the Go oracle in
// oracle/*.ref (built with the local Go toolchain); this file only supplies the inputs.
// Deterministic; run: ms run bench/agent/gen.ms -- c61
import (
	Cases, build_oracle, write_cases from "../../lib/gen.ms",
	Random, seeded from "../../lib/pyrandom.ms",
)

fn add(var cs Cases, name String, script String) Void {
	cs.push(name, script)
}

// A registry of `n` packages p0..p{n-1}; package pI has `versions` releases and depends
// on up to three lower-numbered packages with random constraints, so the search has to
// backtrack. Ends with a `resolve` of the highest package.
fn random_registry(seed Int, n Int, versions Int) String {
	var rng = seeded(seed)
	ops := ["^", "~", ">=", "<=", "", "<", ">"]
	var out = ""

	for i in 0..n {
		for v in 0..versions {
			var line = f"pkg p{i} {rng.randint(0, 2)}.{v}.{rng.randint(0, 3)}"
			var used = List[Int]()

			for _k in 0..rng.randint(0, 3) {
				if i == 0 { break }

				j := rng.randint(0, i - 1)
				if used.contains(j) { continue }

				used.append(j)

				op := rng.choice(ops)
				line += f" p{j}:{op}{rng.randint(0, 2)}.{rng.randint(0, versions)}.{rng.randint(0, 3)}"
			}

			out += line + "\n"
		}
	}

	out += f"resolve p{n - 1} *\n"
	out += f"resolve p{n / 2} ^0.1.0\n"
	out += "list p0\n"
	return out
}

export fn gen_c61() Void {
	var cs = Cases(build_oracle("c61-dep-resolver"))
	add(
		cs,
		"basic",
		"pkg a 1.0.0 b:^1.0.0 c:>=1.0.0,<3.0.0\npkg b 1.2.0 c:^2.0.0\npkg b 1.0.0\npkg c 2.5.1\npkg c 3.1.0\nresolve a *\nlist b\nresolve a =9.9.9\nresolve z *\n",
	)
	add(
		cs,
		"constraint-forms",
		"pkg x 0.0.3\npkg x 0.2.3\npkg x 0.2.9\npkg x 0.3.0\npkg x 1.2.3\npkg x 1.2.9\npkg x 1.3.0\npkg x 2.0.0\nresolve x ^0.0.3\nresolve x ^0.2.3\nresolve x ^1.2.3\nresolve x ~1.2.3\nresolve x ~0.2.3\nresolve x >1.2.3\nresolve x >=1.2.3,<1.3.0\nresolve x <1.0.0\nresolve x <=0.2.9\nresolve x 1.2.9\nresolve x =1.3.0\nresolve x >=1.0.0,<=1.2.9,>1.2.3\nresolve x *\nresolve x ^2.0.0\nresolve x ^2.0.1\n",
	)
	add(
		cs,
		"constraint-errors",
		"pkg x 1.0.0\nresolve x\nresolve x ^\nresolve x >=1.0\nresolve x ^1.0.0,\nresolve x ,*\nresolve x =>1.0.0\nresolve x 01.0.0\nresolve x 1.0.0.0\nresolve x 1.a.0\nresolve x 1000000.0.0\nresolve x 999999.0.0\nresolve x *,*\nresolve x >= 1.0.0\nresolve x ^1.0.0 extra\n",
	)
	add(
		cs,
		"pkg-errors",
		"pkg\npkg a\npkg A 1.0.0\npkg a 1.0\npkg a 1.0.0 b\npkg a 1.0.0 B:*\npkg a 1.0.0 b:\npkg a 1.0.0 b:^x\npkg a 1.0.0 b:* b:^1.0.0\npkg a 1.0.0 b:* c:??\npkg a 1.0.0 :*\npkg a 1.0.0\npkg a 1.0.0\npkg a 1.0.0 b:*\npkg a 2.0.0 b:*   c:^1.0.0\nlist a\nlist b\nlist\nlist a b\nfrob\nresolve\nresolve a\n",
	)
	add(
		cs,
		"backtracking",
		"pkg app 1.0.0 lib:*  util:^1.0.0\npkg lib 2.0.0 util:^2.0.0\npkg lib 1.5.0 util:^1.2.0\npkg lib 1.0.0 util:^1.0.0\npkg util 2.1.0\npkg util 1.4.0\npkg util 1.0.0\nresolve app *\npkg app 2.0.0 lib:^2.0.0 util:^1.0.0\nresolve app ^2.0.0\nresolve app =1.0.0\n",
	)
	add(
		cs,
		"order-matters",
		"pkg a 1.0.0 b:* c:*\npkg b 2.0.0 d:^2.0.0\npkg b 1.0.0 d:^1.0.0\npkg c 1.0.0 d:^1.0.0\npkg d 2.0.0\npkg d 1.0.0\nresolve a *\npkg c 2.0.0 d:^2.0.0\nresolve a *\nresolve a ^1.0.0\n",
	)
	add(
		cs,
		"unknown-package",
		"pkg a 1.0.0 b:* c:*\npkg b 1.0.0 ghost:*\nresolve a *\nresolve ghost *\nresolve b *\npkg ghost 1.0.0\nresolve a *\nresolve a =1.0.0\n",
	)
	add(
		cs,
		"unknown-after-backtrack",
		"pkg a 2.0.0 b:^2.0.0\npkg a 1.0.0 b:^1.0.0\npkg b 1.0.0 ghost:*\nresolve a *\nresolve a ^2.0.0\npkg b 2.0.0\nresolve a *\n",
	)
	add(
		cs,
		"cycles",
		"pkg a 1.0.0 b:*\npkg b 1.0.0 a:*\nresolve a *\nresolve b *\npkg a 2.0.0 b:^2.0.0\npkg b 2.0.0 a:^1.0.0\nresolve a *\nresolve a ^2.0.0\npkg c 1.0.0 c:^1.0.0\nresolve c *\npkg d 1.0.0 d:^2.0.0\nresolve d *\n",
	)
	add(
		cs,
		"diamond",
		"pkg top 1.0.0 left:* right:*\npkg left 1.0.0 base:>=1.0.0\npkg right 1.0.0 base:<=1.5.0\npkg base 2.0.0\npkg base 1.5.0\npkg base 1.0.0\npkg base 0.9.0\nresolve top *\nresolve left *\nresolve right ^1.0.0\n",
	)
	add(
		cs,
		"duplicate-release",
		"pkg a 1.0.0\npkg a 1.0.0\npkg a 1.0.0 b:*\npkg a 1.1.0\nlist a\npkg b 0.0.1\npkg b 0.0.2\npkg b 0.1.0\nresolve a ^1.0.0\nresolve b ^0.0.1\nresolve b ^0.0.2\nresolve b ^0.1.0\nresolve b ^0.0.0\n",
	)
	add(cs, "random-small", random_registry(11, 6, 3))
	add(cs, "random-medium", random_registry(23, 12, 4))
	add(cs, "random-wide", random_registry(37, 20, 3))
	add(cs, "random-deep", random_registry(53, 30, 2))
	add(cs, "random-dense", random_registry(71, 10, 6))

	examples := [
		cs.make(
			"ex-basic",
			"pkg a 1.0.0 b:^1.0.0 c:>=1.0.0,<3.0.0\npkg b 1.2.0 c:^2.0.0\npkg b 1.0.0\npkg c 2.5.1\npkg c 3.1.0\nresolve a *\nlist b\nresolve a =9.9.9\nresolve z *\n",
		),
		cs.make(
			"ex-backtrack",
			"pkg app 1.0.0 lib:* util:^1.0.0\npkg lib 2.0.0 util:^2.0.0\npkg lib 1.0.0 util:^1.0.0\npkg util 2.0.0\npkg util 1.0.0\nresolve app *\nresolve lib ^2.0.0\npkg x 1.0.0 y:*\nresolve x *\n",
		),
	]
	write_cases("c61-dep-resolver", examples, cs.list)
}
