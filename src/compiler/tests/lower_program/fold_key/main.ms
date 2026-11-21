fn tidy(text: String) String:
	return text.trim().trim_start().trim_end().replace("a", "b").upper().lower()

fn main() Void:
	print(tidy(" Straße "))
	print("Straße".equal_fold("STRASSE"))
