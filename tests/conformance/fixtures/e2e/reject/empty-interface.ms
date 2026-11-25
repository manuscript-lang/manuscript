// conform: tags=testing,tier-core
// conform: phase=check
interface Marker { ... }

export fn main() Int {
	return 0
}
// expect-error: MS3000 3:1 an interface declares at least one operation; only the standard library declares a property without operations, like `Data`
