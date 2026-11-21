fn bad() Error:
	return Error("invalid input", kind: "EINVAL")

fn main() Void:
	print(bad().message)
