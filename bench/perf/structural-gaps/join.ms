fn main() Unit:
	var total = 0
	for i in 0..300000:
		row := ["id{i}", "name", "city", "{i * 7}", "zz"].join(",")
		total += row.length()
	print("{total}")
