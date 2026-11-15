fn main() Void:
	words := "a,b".split(",")
	print(words.join("-").trim())
