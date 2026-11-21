fn log_line(text: String) Void:
	print(text)

fn middle(text: String) Void:
	log_line(text)

fn pure_top(text: String) Void:
	middle(text)

fn main() Int:
	pure_top("a")
	return 0
