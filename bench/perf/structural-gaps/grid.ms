fn lcs(a: List[Int], b: List[Int]) Int:
	var dp = List[List[Int]]()
	var i = 0
	while i <= a.length():
		var row = List[Int]()
		var j = 0
		while j <= b.length():
			row.append(0)
			j += 1
		dp.append(row)
		i += 1
	i = 1
	while i <= a.length():
		var j = 1
		while j <= b.length():
			if a[i - 1] == b[j - 1]:
				dp[i][j] = dp[i - 1][j - 1] + 1
			else if dp[i - 1][j] >= dp[i][j - 1]:
				dp[i][j] = dp[i - 1][j]
			else:
				dp[i][j] = dp[i][j - 1]
			j += 1
		i += 1
	return dp[a.length()][b.length()]

fn main() Unit:
	var a = List[Int]()
	var b = List[Int]()
	var x = 12345
	var k = 0
	while k < 2000:
		x = (x * 1103515245 + 12345) % 2147483648
		a.append((x / 65536) % 4)
		x = (x * 1103515245 + 12345) % 2147483648
		b.append((x / 65536) % 4)
		k += 1
	print(lcs(a, b))
