// conform: tags=scope-cleanup,resources,tier-io
// conform: phase=run
// Ownership shapes the verifier used to skip: a result bound while its statement's
// temporary resource closes, a loop that keeps a list across `continue`, an `if`
// binding of a view that is handed on, and a resource moved through a function that
// answers its argument.
import OpenMode, OpenOptions, open, read_file from "@std/os/fs.ms"

type Lang {
	id String
	context List[String]
}

fn identity[T](result T!) T! => result

fn unreadable(path String) String {
	read := read_file(path).wait()

	if bytes := read {
		return bytes.decode_utf8() or ""
	} else {
		return "unreadable"
	}
}

fn languages(ids List[String], names List[String]) List[Lang] {
	var out = List[Lang]()
	var known = List[String]()

	for name in names {
		known.append(name.clone())
		if not ids.is_empty() and not ids.contains(
			name
		) { continue }

		var context = List[String]()
		context.append(name.clone())
		out.append(Lang(name.clone(), context))
	}

	return out
}

fn parsed(lines List[String]) List[String] {
	var out = List[String]()

	for line in lines {
		r := identity(ok(line.clone()))
		event := r.to_optional()
		if event != null { out.append(event) }
	}

	return out
}

fn opened(path String) Void! {
	var file = identity(open(path, OpenMode.ReadWrite, OpenOptions(permissions: 384)))?
	file.close()?
}

fn main() Void {
	print(unreadable("/nonexistent/owner-flows"))
	print(languages(["b"], ["a", "b", "c"]).length().to_string())
	print(parsed(["x", "y"]).length().to_string())
	print(opened("/nonexistent/owner-flows").is_error().to_string())
}
