// conform: tags=diagnostics
// conform: phase=check
fn poll_literal_up(log List[Int], start Int) Void {
	var i = -137

	while i < 1000 {
		log.append(i)
		i += 1
	}
}

fn poll_literal_down(log List[Int], start Int) Void {
	var i = 500

	while i > 0 {
		log.append(i)
		i -= 1
	}
}

fn poll_literal_nested(log List[Int], start Int) Void {
	var outer = 0

	while outer < 3 {
		var i = 0

		while i < 70 {
			log.append(i)
			i += 1
		}

		outer += 1
	}
}

fn poll_up(log List[Int], start Int) Void {
	var i = start

	while i < 1000 {
		log.append(i)
		i += 1
	}
}

fn poll_down(log List[Int], start Int) Void {
	var i = start

	while i > 0 {
		log.append(i)
		i -= 1
	}
}

fn poll_continue(log List[Int], start Int) Void {
	var i = start
	var skips = 0

	while i < 1000 {
		if skips < 5 {
			skips += 1
			continue
		}

		log.append(i)
		i += 1
	}
}

fn poll_reset(log List[Int], start Int) Void {
	var i = start

	while i < 1000 {
		log.append(i)
		i += 1
		if i == 5 {
			i = 0
		}
	}
}

fn poll_nested(log List[Int], start Int) Void {
	var outer = 0

	while outer < 3 {
		var i = outer

		while i < 70 {
			log.append(i)
			i += 1
		}

		outer += 1
	}
}
// expect-error: MS3000 7:9 cannot change `log`: parameter `log` is not declared var; write `var log <Type>` in the signature
// expect-fix: 3:20-3:20 "var "
// expect-error: MS3000 16:9 cannot change `log`: parameter `log` is not declared var; write `var log <Type>` in the signature
// expect-fix: 12:22-12:22 "var "
// expect-error: MS3000 28:13 cannot change `log`: parameter `log` is not declared var; write `var log <Type>` in the signature
// expect-fix: 21:24-21:24 "var "
// expect-error: MS3000 40:9 cannot change `log`: parameter `log` is not declared var; write `var log <Type>` in the signature
// expect-fix: 36:12-36:12 "var "
// expect-error: MS3000 49:9 cannot change `log`: parameter `log` is not declared var; write `var log <Type>` in the signature
// expect-fix: 45:14-45:14 "var "
// expect-error: MS3000 64:9 cannot change `log`: parameter `log` is not declared var; write `var log <Type>` in the signature
// expect-fix: 54:18-54:18 "var "
// expect-error: MS3000 73:9 cannot change `log`: parameter `log` is not declared var; write `var log <Type>` in the signature
// expect-fix: 69:15-69:15 "var "
// expect-error: MS3000 88:13 cannot change `log`: parameter `log` is not declared var; write `var log <Type>` in the signature
// expect-fix: 81:16-81:16 "var "
