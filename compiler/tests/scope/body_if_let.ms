// `if name = optional` forms the C body checker claims.
fn payload_or(d: Int, o: Int?) Int:
	if n := o: return n + 1
	return d

fn payload_else(o: Int?) Int:
	if n := o:
		return n
	else:
		return 0

fn text_payload(d: String, o: String?) String:
	if t := o: return t
	return d

fn nested(a: Int?, b: Int?) Int:
	if x := a:
		if y := b: return x + y
		return x

	return 0

fn unused_payload(o: Int?) Int:
	if n := o: return 1
	return 0
