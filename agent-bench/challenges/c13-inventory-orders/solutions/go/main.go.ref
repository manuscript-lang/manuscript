package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strings"
)

var arity = map[string]int{"stock": 3, "price": 3, "cancel": 2, "ship": 2, "report": 1}

type item struct {
	sku string
	qty int
}

type order struct {
	items  []item
	status string
	total  int
}

var stock = map[string]int{}
var price = map[string]int{}
var orders = map[string]*order{}

func money(c int) string { return fmt.Sprintf("%d.%02d", c/100, c%100) }

func validChars(s string, ok func(c byte) bool) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		if !ok(s[i]) {
			return false
		}
	}
	return true
}

func validSKU(s string) bool {
	return validChars(s, func(c byte) bool { return (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' })
}

func validOID(s string) bool {
	return validChars(s, func(c byte) bool { return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' })
}

// number parses 1 to 7 ASCII digits.
func number(s string) (int, bool) {
	if len(s) > 7 || !validChars(s, func(c byte) bool { return c >= '0' && c <= '9' }) {
		return 0, false
	}
	n := 0
	for i := 0; i < len(s); i++ {
		n = n*10 + int(s[i]-'0')
	}
	return n, true
}

func qty(s string) (int, bool) {
	n, ok := number(s)
	return n, ok && n >= 1 && n <= 100000
}

func exec(line string) []string {
	t := strings.Split(line, " ")
	c := t[0]
	want, known := arity[c]
	if !known && c != "order" {
		return []string{"error: unknown command"}
	}
	if (c == "order" && len(t) < 3) || (c != "order" && len(t) != want) {
		return []string{"error: usage"}
	}
	switch c {
	case "stock":
		if !validSKU(t[1]) {
			return []string{"error: bad sku"}
		}
		q, ok := qty(t[2])
		if !ok {
			return []string{"error: bad quantity"}
		}
		stock[t[1]] += q
		if _, has := price[t[1]]; !has {
			price[t[1]] = 0
		}
		return []string{fmt.Sprintf("ok %s stock=%d", t[1], stock[t[1]])}
	case "price":
		p, ok := number(t[2])
		if !ok || p > 10000000 {
			return []string{"error: bad price"}
		}
		if _, has := stock[t[1]]; !has {
			return []string{"error: unknown sku " + t[1]}
		}
		price[t[1]] = p
		return []string{"ok"}
	case "order":
		id := t[1]
		if !validOID(id) {
			return []string{"error: bad order id"}
		}
		if orders[id] != nil {
			return []string{"error: order " + id + " already exists"}
		}
		var items []item
		for _, tok := range t[2:] {
			p := strings.Split(tok, ":")
			if len(p) != 2 || !validSKU(p[0]) {
				return []string{"error: bad item " + tok}
			}
			q, ok := qty(p[1])
			if !ok {
				return []string{"error: bad item " + tok}
			}
			items = append(items, item{p[0], q})
		}
		seen := map[string]bool{}
		for _, it := range items {
			if seen[it.sku] {
				return []string{"error: duplicate sku " + it.sku}
			}
			have, known := stock[it.sku]
			if !known {
				return []string{"error: unknown sku " + it.sku}
			}
			if it.qty > have {
				return []string{fmt.Sprintf("error: insufficient stock for %s (have %d, need %d)", it.sku, have, it.qty)}
			}
			seen[it.sku] = true
		}
		total := 0
		for _, it := range items {
			stock[it.sku] -= it.qty
			if it.qty >= 10 {
				total += (it.qty*price[it.sku]*90 + 50) / 100
			} else {
				total += it.qty * price[it.sku]
			}
		}
		orders[id] = &order{items, "placed", total}
		return []string{fmt.Sprintf("ok %s total=%s", id, money(total))}
	case "cancel", "ship":
		o := orders[t[1]]
		if o == nil {
			return []string{"error: unknown order " + t[1]}
		}
		if c == "cancel" {
			if o.status != "placed" {
				return []string{"error: order " + t[1] + " already " + o.status}
			}
			for _, it := range o.items {
				stock[it.sku] += it.qty
			}
			o.status = "cancelled"
			return []string{"ok"}
		}
		if o.status == "shipped" {
			return []string{"error: order " + t[1] + " already shipped"}
		}
		if o.status == "cancelled" {
			return []string{"error: order " + t[1] + " is cancelled"}
		}
		o.status = "shipped"
		return []string{"ok"}
	}
	reserved := map[string]int{}
	counts := map[string]int{}
	revenue := 0
	for _, o := range orders {
		counts[o.status]++
		if o.status == "placed" {
			for _, it := range o.items {
				reserved[it.sku] += it.qty
			}
		}
		if o.status == "shipped" {
			revenue += o.total
		}
	}
	skus := make([]string, 0, len(stock))
	for s := range stock {
		skus = append(skus, s)
	}
	sort.Strings(skus)
	var out []string
	for _, s := range skus {
		out = append(out, fmt.Sprintf("%s stock=%d price=%s reserved=%d", s, stock[s], money(price[s]), reserved[s]))
	}
	out = append(out, fmt.Sprintf("orders placed=%d shipped=%d cancelled=%d", counts["placed"], counts["shipped"], counts["cancelled"]))
	out = append(out, "revenue="+money(revenue))
	return out
}

func main() {
	sc := bufio.NewScanner(os.Stdin)
	sc.Buffer(make([]byte, 1<<20), 1<<24)
	w := bufio.NewWriter(os.Stdout)
	defer w.Flush()
	for sc.Scan() {
		l := sc.Text()
		if strings.Trim(l, " ") == "" {
			continue
		}
		for _, o := range exec(l) {
			fmt.Fprintln(w, o)
		}
	}
}
