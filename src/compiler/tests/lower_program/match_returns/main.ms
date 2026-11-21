enum Seek:
	Start
	Current
	End

fn a(origin: Seek) Int:
	match origin:
		Start: return 0
		Current: return 1
		End: return 2

fn b(status: Int) String:
	match status:
		400: return "Bad Request"
		_: return "Error"

fn c(origin: Seek) Int:
	return match origin:
		Start: 0
		Current: 1
		End: 2

fn main() Void:
	print(a(Seek.End))
	print(b(400))
	print(c(Seek.End))
