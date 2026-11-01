package main

import (
	"bufio"
	"os"
	"strings"
)

const badCommand = "error: bad command"

func main() {
	reader := bufio.NewReaderSize(os.Stdin, 1<<20)
	writer := bufio.NewWriterSize(os.Stdout, 1<<20)
	defer writer.Flush()

	for {
		line, err := reader.ReadString('\n')
		if out, emit := processLine(line); emit {
			writer.WriteString(out)
			writer.WriteByte('\n')
		}
		if err != nil {
			break
		}
	}
}

// processLine returns the output for one input line. emit is false for a
// blank line (empty or only spaces), which produces no output at all.
func processLine(raw string) (out string, emit bool) {
	line := strings.TrimSuffix(raw, "\n")
	line = strings.TrimSuffix(line, "\r")
	if strings.Trim(line, " ") == "" {
		return "", false
	}
	tokens := strings.Split(line, " ")
	out, ok := runCommand(tokens)
	if !ok {
		return badCommand, true
	}
	return out, true
}

func runCommand(tokens []string) (string, bool) {
	switch tokens[0] {
	case "lcs":
		if len(tokens) != 3 || !validStr(tokens[1]) || !validStr(tokens[2]) {
			return "", false
		}
		return itoa(lcs(tokens[1], tokens[2])), true
	case "edit":
		if len(tokens) != 3 || !validStr(tokens[1]) || !validStr(tokens[2]) {
			return "", false
		}
		return itoa(editDistance(tokens[1], tokens[2])), true
	case "knap":
		if len(tokens) < 2 {
			return "", false
		}
		capacity, ok := parseNum(tokens[1])
		if !ok {
			return "", false
		}
		ws := make([]int, 0, len(tokens)-2)
		vs := make([]int, 0, len(tokens)-2)
		for _, t := range tokens[2:] {
			w, v, ok := parseItem(t)
			if !ok {
				return "", false
			}
			ws = append(ws, w)
			vs = append(vs, v)
		}
		return itoa(knapsack(capacity, ws, vs)), true
	case "coins":
		if len(tokens) < 3 {
			return "", false
		}
		amount, ok := parseNum(tokens[1])
		if !ok {
			return "", false
		}
		coins := make([]int, 0, len(tokens)-2)
		for _, t := range tokens[2:] {
			c, ok := parsePositive(t)
			if !ok {
				return "", false
			}
			coins = append(coins, c)
		}
		n := minCoins(amount, coins)
		if n < 0 {
			return "impossible", true
		}
		return itoa(n), true
	}
	return "", false
}

// validStr reports whether a string operand is non-empty. Spaces cannot occur
// because the line was split on them.
func validStr(s string) bool {
	return len(s) > 0
}

// parseNum parses a 1 to 6 digit decimal number with no sign.
func parseNum(s string) (int, bool) {
	if len(s) < 1 || len(s) > 6 {
		return 0, false
	}
	n := 0
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c < '0' || c > '9' {
			return 0, false
		}
		n = n*10 + int(c-'0')
	}
	return n, true
}

// parsePositive parses a number that must be at least 1.
func parsePositive(s string) (int, bool) {
	n, ok := parseNum(s)
	if !ok || n < 1 {
		return 0, false
	}
	return n, true
}

// parseItem parses "w:v" where w >= 1 and v >= 0.
func parseItem(s string) (int, int, bool) {
	idx := strings.IndexByte(s, ':')
	if idx < 0 || strings.IndexByte(s[idx+1:], ':') >= 0 {
		return 0, 0, false
	}
	w, ok := parsePositive(s[:idx])
	if !ok {
		return 0, 0, false
	}
	v, ok := parseNum(s[idx+1:])
	if !ok {
		return 0, 0, false
	}
	return w, v, true
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var buf [24]byte
	i := len(buf)
	neg := n < 0
	if neg {
		n = -n
	}
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}

// lcs returns the length of the longest common subsequence of a and b.
func lcs(a, b string) int {
	if len(a) < len(b) {
		a, b = b, a
	}
	prev := make([]int, len(b)+1)
	cur := make([]int, len(b)+1)
	for i := 0; i < len(a); i++ {
		for j := 1; j <= len(b); j++ {
			if a[i] == b[j-1] {
				cur[j] = prev[j-1] + 1
			} else if prev[j] >= cur[j-1] {
				cur[j] = prev[j]
			} else {
				cur[j] = cur[j-1]
			}
		}
		prev, cur = cur, prev
	}
	return prev[len(b)]
}

// editDistance returns the Levenshtein distance between a and b.
func editDistance(a, b string) int {
	if len(a) < len(b) {
		a, b = b, a
	}
	prev := make([]int, len(b)+1)
	cur := make([]int, len(b)+1)
	for j := range prev {
		prev[j] = j
	}
	for i := 1; i <= len(a); i++ {
		cur[0] = i
		for j := 1; j <= len(b); j++ {
			cost := 1
			if a[i-1] == b[j-1] {
				cost = 0
			}
			best := prev[j-1] + cost
			if prev[j]+1 < best {
				best = prev[j] + 1
			}
			if cur[j-1]+1 < best {
				best = cur[j-1] + 1
			}
			cur[j] = best
		}
		prev, cur = cur, prev
	}
	return prev[len(b)]
}

// knapsack solves 0/1 knapsack. Items with weight > capacity are skipped.
func knapsack(capacity int, ws, vs []int) int {
	total := 0
	for _, w := range ws {
		total += w
	}
	// If everything fits, take all items; otherwise the DP range is bounded by
	// the capacity, which keeps the table no larger than necessary.
	if total <= capacity {
		sum := 0
		for _, v := range vs {
			sum += v
		}
		return sum
	}
	dp := make([]int, capacity+1)
	for i := range ws {
		w, v := ws[i], vs[i]
		if w > capacity {
			continue
		}
		for c := capacity; c >= w; c-- {
			if cand := dp[c-w] + v; cand > dp[c] {
				dp[c] = cand
			}
		}
	}
	return dp[capacity]
}

// minCoins returns the minimum number of coins summing to amount, or -1 if impossible.
func minCoins(amount int, coins []int) int {
	const inf = int(^uint(0) >> 1)
	// Deduplicate and drop denominations larger than the amount.
	seen := make(map[int]bool, len(coins))
	uniq := make([]int, 0, len(coins))
	for _, c := range coins {
		if c <= amount && !seen[c] {
			seen[c] = true
			uniq = append(uniq, c)
		}
	}
	dp := make([]int, amount+1)
	for i := 1; i <= amount; i++ {
		dp[i] = inf
	}
	for _, c := range uniq {
		for x := c; x <= amount; x++ {
			if dp[x-c] != inf && dp[x-c]+1 < dp[x] {
				dp[x] = dp[x-c] + 1
			}
		}
	}
	if dp[amount] == inf {
		return -1
	}
	return dp[amount]
}
