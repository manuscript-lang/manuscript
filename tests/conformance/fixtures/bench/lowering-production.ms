// conform: tags=control-flow,diagnostics,interfaces,modules,mutation,numbers,records,stdlib-cleanup,stdlib-collections,strings,tier-stdlib,scope-cleanup
// conform: phase=check
// conform: origin=bench/perf/lowering/production.ms
import Closeable from "@std/core.ms"

type Resource {
	value Int
}

fn move Resource.close() Void! => return ok()

fn empty(value Int) Int => value

fn kept(move resource Resource) Int {
	_active := resource
	return 1
}

fn ints(left Int, right Int, limit Int, move resource Resource) Int {
	_active := resource
	var count = 0
	for index in 0..limit {
		if left == right { count += 1 }
	}
	return count
}

fn floats(left Float, right Float, limit Int, move resource Resource) Int {
	_active := resource
	var count = 0
	for index in 0..limit {
		if left == right { count += 1 }
	}
	return count
}

fn bools(left Bool, right Bool, limit Int, move resource Resource) Int {
	_active := resource
	var count = 0
	for index in 0..limit {
		if left == right { count += 1 }
	}
	return count
}

fn strings(left String, right String, limit Int, move resource Resource) Int {
	_active := resource
	var count = 0
	for index in 0..limit {
		if left == right { count += 1 }
	}
	return count
}
