package main

import (
	"bufio"
	"fmt"
	"io"
	"math/big"
	"os"
	"sort"
	"strings"
)

// parseLine splits one record into category and amount text.
// It returns ok=false if the line is invalid under the task rules.
func parseLine(line string) (category, amount string, ok bool) {
	if strings.HasPrefix(line, `"`) {
		// Quoted category: ends at the next double quote (no escaping).
		end := strings.IndexByte(line[1:], '"')
		if end < 0 {
			return "", "", false
		}
		end++ // index of closing quote within line
		category = line[1:end]
		rest := line[end+1:]
		if !strings.HasPrefix(rest, ",") {
			return "", "", false
		}
		amount = rest[1:]
	} else {
		// Unquoted category: must not contain a comma; split at the only comma.
		idx := strings.IndexByte(line, ',')
		if idx < 0 {
			return "", "", false
		}
		category = line[:idx]
		amount = line[idx+1:]
	}
	if category == "" {
		return "", "", false
	}
	if !validAmount(amount) {
		return "", "", false
	}
	return category, amount, true
}

// validAmount accepts digits, optionally followed by '.' and one or two digits.
func validAmount(s string) bool {
	intPart, frac, hasDot := strings.Cut(s, ".")
	if intPart == "" {
		return false
	}
	if !allDigits(intPart) {
		return false
	}
	if hasDot {
		if len(frac) < 1 || len(frac) > 2 || !allDigits(frac) {
			return false
		}
	}
	return true
}

func allDigits(s string) bool {
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			return false
		}
	}
	return true
}

// amountCents converts a validated amount to an exact integer count of hundredths.
func amountCents(s string) *big.Int {
	intPart, frac, _ := strings.Cut(s, ".")
	for len(frac) < 2 {
		frac += "0"
	}
	v := new(big.Int)
	v.SetString(intPart+frac, 10)
	return v
}

func run(in io.Reader, out io.Writer) error {
	sums := map[string]*big.Int{}
	skipped := 0

	r := bufio.NewReaderSize(in, 1<<16)
	for {
		line, err := r.ReadString('\n')
		if len(line) > 0 || err == nil {
			line = strings.TrimSuffix(line, "\n")
			line = strings.TrimSuffix(line, "\r")
			if line != "" {
				if cat, amt, ok := parseLine(line); ok {
					c := amountCents(amt)
					if cur, found := sums[cat]; found {
						cur.Add(cur, c)
					} else {
						sums[cat] = c
					}
				} else {
					skipped++
				}
			}
		}
		if err != nil {
			if err == io.EOF {
				break
			}
			return err
		}
	}

	cats := make([]string, 0, len(sums))
	for c := range sums {
		cats = append(cats, c)
	}
	sort.Strings(cats) // byte-order comparison

	w := bufio.NewWriter(out)
	defer w.Flush()
	for _, c := range cats {
		total := sums[c]
		q, rem := new(big.Int).QuoRem(total, big.NewInt(100), new(big.Int))
		fmt.Fprintf(w, "%s: %s.%02d\n", c, q.String(), rem.Int64())
	}
	if skipped > 0 {
		fmt.Fprintf(w, "skipped: %d\n", skipped)
	}
	return nil
}

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
