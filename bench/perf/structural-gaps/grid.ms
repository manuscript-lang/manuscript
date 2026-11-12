fn lcs(a: List[Int], b: List[Int]) Int:
	n := a.length()
	m := b.length()
	var dp: List[List[Int]] = []
	for i in 0..n + 1:
		dp.append([0].repeated(m + 1))

	for i in 1..n + 1:
		for j in 1..m + 1:
			if a[i - 1] == b[j - 1]:
				dp[i][j] = dp[i - 1][j - 1] + 1
			else if dp[i - 1][j] >= dp[i][j - 1]:
				dp[i][j] = dp[i - 1][j]
			else:
				dp[i][j] = dp[i][j - 1]

	return dp[n][m]

fn main() Unit:
	var a: List[Int] = []
	var b: List[Int] = []

	for i in 0..2000:
		a.append(i * 7 % 13)
		b.append(i * 5 % 11)

	print("{lcs(a, b)}")
