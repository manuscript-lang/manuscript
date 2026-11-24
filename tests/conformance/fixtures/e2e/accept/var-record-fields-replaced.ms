// conform: tags=ownership,var-parameters
// conform: phase=run
type Index:
	hits Int
	names Map[String, Int]
	order List[String]

fn remember(var index Index, name String) Void:
	index.hits += 1
	index.names[name.clone()] = index.hits
	index.order.append(name.clone())

fn copy_from(var index Index, other Index) Void:
	index.hits = other.hits
	index.names = other.names.clone()
	index.order = other.order.clone()

fn main() Void:
	var a = Index(0, Map[String, Int](), [])
	remember(a, "x")
	remember(a, "y")
	var b = Index(0, Map[String, Int](), ["old"])
	copy_from(b, a)
	remember(b, "z")
	print(f"{a.hits} {a.names.length()} {a.order.length()}")
	print(f"{b.hits} {b.names.length()} {b.order.length()}")
