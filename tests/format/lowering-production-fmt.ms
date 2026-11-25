// conform: tags=control-flow,formatter,interfaces,modules,mutation,numbers,parser,records,stdlib-cleanup,stdlib-collections,strings,tier-stdlib,scope-cleanup
// conform: phase=parse
// conform: origin=bench/perf/lowering/production.ms
import Closeable from "@std/core.ms"

type Resource {
	value Int
}

fn Resource.close() Void! => return ok()

fn empty(value Int) Int => value

fn kept(resource Resource) Int {
	_active := resource
	return 1
}

fn ints(left Int, right Int, limit Int, resource Resource) Int {
	_active := resource
	var count = 0
	for index in 0..limit {
		if left == right { count += 1 }
	}
	return count
}

fn floats(left Float, right Float, limit Int, resource Resource) Int {
	_active := resource
	var count = 0
	for index in 0..limit {
		if left == right { count += 1 }
	}
	return count
}

fn bools(left Bool, right Bool, limit Int, resource Resource) Int {
	_active := resource
	var count = 0
	for index in 0..limit {
		if left == right { count += 1 }
	}
	return count
}

fn strings(left String, right String, limit Int, resource Resource) Int {
	_active := resource
	var count = 0
	for index in 0..limit {
		if left == right { count += 1 }
	}
	return count
}
// expect-format: rewritten
// expect-formatted: import Closeable from "@std/core.ms"
// expect-formatted:
// expect-formatted: type Resource {
// expect-formatted: \tvalue Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn Resource.close() Void! => return ok()
// expect-formatted:
// expect-formatted: fn empty(value Int) Int => value
// expect-formatted:
// expect-formatted: fn kept(resource Resource) Int {
// expect-formatted: \t_active := resource
// expect-formatted: \treturn 1
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn ints(left, right, limit Int, resource Resource) Int {
// expect-formatted: \t_active := resource
// expect-formatted: \tvar count = 0
// expect-formatted: \tfor index in 0..limit {
// expect-formatted: \t\tif left == right { count += 1 }
// expect-formatted: \t}
// expect-formatted: \treturn count
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn floats(left, right Float, limit Int, resource Resource) Int {
// expect-formatted: \t_active := resource
// expect-formatted: \tvar count = 0
// expect-formatted: \tfor index in 0..limit {
// expect-formatted: \t\tif left == right { count += 1 }
// expect-formatted: \t}
// expect-formatted: \treturn count
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn bools(left, right Bool, limit Int, resource Resource) Int {
// expect-formatted: \t_active := resource
// expect-formatted: \tvar count = 0
// expect-formatted: \tfor index in 0..limit {
// expect-formatted: \t\tif left == right { count += 1 }
// expect-formatted: \t}
// expect-formatted: \treturn count
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn strings(left, right String, limit Int, resource Resource) Int {
// expect-formatted: \t_active := resource
// expect-formatted: \tvar count = 0
// expect-formatted: \tfor index in 0..limit {
// expect-formatted: \t\tif left == right { count += 1 }
// expect-formatted: \t}
// expect-formatted: \treturn count
// expect-formatted: }
