package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"
	"time"
)

const (
	minYear     = 1970
	maxYear     = 2099
	maxCount    = 20
	searchDays  = 3000
	scanBufSize = 1 << 20
)

// fieldSpec describes one cron field's range and error label.
type fieldSpec struct {
	name   string
	lo, hi int
	errMsg string
}

var cronFields = []fieldSpec{
	{"minute", 0, 59, "bad minute"},
	{"hour", 0, 23, "bad hour"},
	{"day-of-month", 1, 31, "bad day-of-month"},
	{"month", 1, 12, "bad month"},
	{"day-of-week", 0, 6, "bad day-of-week"},
}

// isDigits reports whether s is non-empty and made only of ASCII digits.
func isDigits(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			return false
		}
	}
	return true
}

// parseSmallNum parses a 1-2 digit unsigned number.
func parseSmallNum(s string) (int, bool) {
	if len(s) < 1 || len(s) > 2 || !isDigits(s) {
		return 0, false
	}
	v := 0
	for i := 0; i < len(s); i++ {
		v = v*10 + int(s[i]-'0')
	}
	return v, true
}

// parseField parses one cron field into a set of allowed values (indexed by value).
func parseField(s string, lo, hi int) ([]bool, bool) {
	set := make([]bool, hi+1)
	for _, item := range strings.Split(s, ",") {
		if item == "" {
			return nil, false
		}
		rangePart := item
		step := 1
		hasStep := false
		if i := strings.IndexByte(item, '/'); i >= 0 {
			rangePart = item[:i]
			st, ok := parseSmallNum(item[i+1:])
			if !ok || st < 1 {
				return nil, false
			}
			step = st
			hasStep = true
		}

		var a, b int
		if rangePart == "*" {
			a, b = lo, hi
		} else if i := strings.IndexByte(rangePart, '-'); i >= 0 {
			x, ok1 := parseSmallNum(rangePart[:i])
			y, ok2 := parseSmallNum(rangePart[i+1:])
			if !ok1 || !ok2 || x > y || x < lo || y > hi {
				return nil, false
			}
			a, b = x, y
		} else {
			// A single number; a step on a bare number is not in the grammar.
			if hasStep {
				return nil, false
			}
			x, ok := parseSmallNum(rangePart)
			if !ok || x < lo || x > hi {
				return nil, false
			}
			a, b = x, x
		}
		for v := a; v <= b; v += step {
			set[v] = true
		}
	}
	return set, true
}

// parseStart validates START and returns the instant (UTC).
func parseStart(s string) (time.Time, bool) {
	if len(s) != 16 || s[4] != '-' || s[7] != '-' || s[10] != 'T' || s[13] != ':' {
		return time.Time{}, false
	}
	parts := []string{s[0:4], s[5:7], s[8:10], s[11:13], s[14:16]}
	nums := make([]int, len(parts))
	for i, p := range parts {
		v, ok := parseSmallNum(p)
		if !ok && len(p) == 4 {
			// Four-digit year: parse manually.
			if !isDigits(p) {
				return time.Time{}, false
			}
			v = 0
			for j := 0; j < len(p); j++ {
				v = v*10 + int(p[j]-'0')
			}
			ok = true
		}
		if !ok {
			return time.Time{}, false
		}
		nums[i] = v
	}
	year, month, day, hour, minute := nums[0], nums[1], nums[2], nums[3], nums[4]
	if year < minYear || year > maxYear || month < 1 || month > 12 {
		return time.Time{}, false
	}
	if day < 1 || day > daysIn(year, month) {
		return time.Time{}, false
	}
	if hour > 23 || minute > 59 {
		return time.Time{}, false
	}
	return time.Date(year, time.Month(month), day, hour, minute, 0, 0, time.UTC), true
}

func isLeap(y int) bool {
	return (y%4 == 0 && y%100 != 0) || y%400 == 0
}

func daysIn(y, m int) int {
	switch m {
	case 2:
		if isLeap(y) {
			return 29
		}
		return 28
	case 4, 6, 9, 11:
		return 30
	}
	return 31
}

// parseCount validates COUNT (1-2 digits, value 1..20).
func parseCount(s string) (int, bool) {
	v, ok := parseSmallNum(s)
	if !ok || v < 1 || v > maxCount {
		return 0, false
	}
	return v, true
}

// process handles one non-blank line and returns the output text for it.
func process(lineNo int, line string) string {
	tokens := strings.Split(line, " ")
	if len(tokens) != 7 {
		return fmt.Sprintf("line %d: error: bad line\n", lineNo)
	}
	start, ok := parseStart(tokens[0])
	if !ok {
		return fmt.Sprintf("line %d: error: bad start\n", lineNo)
	}
	count, ok := parseCount(tokens[1])
	if !ok {
		return fmt.Sprintf("line %d: error: bad count\n", lineNo)
	}
	var sets [5][]bool
	for i, f := range cronFields {
		set, ok := parseField(tokens[2+i], f.lo, f.hi)
		if !ok {
			return fmt.Sprintf("line %d: error: %s\n", lineNo, f.errMsg)
		}
		sets[i] = set
	}
	minSet, hourSet, domSet, monSet, dowSet := sets[0], sets[1], sets[2], sets[3], sets[4]

	startDay := start
	startMinOfDay := start.Hour()*60 + start.Minute()
	endDay := startDay.AddDate(0, 0, searchDays)

	var results []time.Time
	for day := startDay; !day.After(endDay) && len(results) < count; day = day.AddDate(0, 0, 1) {
		if !monSet[int(day.Month())] || !domSet[day.Day()] || !dowSet[int(day.Weekday())] {
			continue
		}
		for h := 0; h < 24 && len(results) < count; h++ {
			if !hourSet[h] {
				continue
			}
			for mi := 0; mi < 60 && len(results) < count; mi++ {
				if !minSet[mi] {
					continue
				}
				if day.Equal(startDay) && h*60+mi <= startMinOfDay {
					continue
				}
				results = append(results, time.Date(day.Year(), day.Month(), day.Day(), h, mi, 0, 0, time.UTC))
			}
		}
	}

	if len(results) == 0 {
		return fmt.Sprintf("line %d: never\n", lineNo)
	}
	var sb strings.Builder
	fmt.Fprintf(&sb, "line %d: %d runs\n", lineNo, len(results))
	for _, r := range results {
		fmt.Fprintf(&sb, "%04d-%02d-%02d %02d:%02d\n", r.Year(), int(r.Month()), r.Day(), r.Hour(), r.Minute())
	}
	return sb.String()
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 0, 64*1024), scanBufSize)
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()

	lineNo := 0
	for scanner.Scan() {
		lineNo++
		line := scanner.Text()
		if strings.Trim(line, " ") == "" {
			continue
		}
		out.WriteString(process(lineNo, line))
	}
}
