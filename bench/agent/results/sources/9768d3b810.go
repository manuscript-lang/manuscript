package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"sort"
	"strings"
)

const (
	statusPlaced = iota
	statusShipped
	statusCancelled
)

type skuRec struct {
	stock int64
	price int64
}

type item struct {
	sku string
	qty int64
}

type order struct {
	status int
	items  []item
	total  int64
}

type store struct {
	skus   map[string]*skuRec
	orders map[string]*order
}

func validSku(s string) bool {
	if len(s) == 0 {
		return false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		if !((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-') {
			return false
		}
	}
	return true
}

func validOrderID(s string) bool {
	if len(s) == 0 {
		return false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		if !((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-') {
			return false
		}
	}
	return true
}

// parseNum parses a "number": 1 to 7 ASCII digits (leading zeros allowed).
func parseNum(s string) (int64, bool) {
	if len(s) < 1 || len(s) > 7 {
		return 0, false
	}
	var v int64
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c < '0' || c > '9' {
			return 0, false
		}
		v = v*10 + int64(c-'0')
	}
	return v, true
}

// parseQty parses a quantity: a number in 1..100000.
func parseQty(s string) (int64, bool) {
	v, ok := parseNum(s)
	if !ok || v < 1 || v > 100000 {
		return 0, false
	}
	return v, true
}

// parsePrice parses a price in cents: a number in 0..10000000 (the 7-digit
// rule means only 0..9999999 can actually be written).
func parsePrice(s string) (int64, bool) {
	v, ok := parseNum(s)
	if !ok || v > 10000000 {
		return 0, false
	}
	return v, true
}

func money(cents int64) string {
	return fmt.Sprintf("%d.%02d", cents/100, cents%100)
}

// lineCost returns the cost in cents of qty units at unit price, with the
// 10% discount applied (round half up) for qty >= 10.
func lineCost(qty, price int64) int64 {
	if qty >= 10 {
		return (qty*price*90 + 50) / 100
	}
	return qty * price
}

func (st *store) run(tokens []string, out *bufio.Writer) {
	cmd := tokens[0]
	n := len(tokens)
	fail := func(msg string) { out.WriteString("error: " + msg + "\n") }

	switch cmd {
	case "stock":
		if n != 3 {
			fail("usage")
			return
		}
		sku := tokens[1]
		if !validSku(sku) {
			fail("bad sku")
			return
		}
		qty, ok := parseQty(tokens[2])
		if !ok {
			fail("bad quantity")
			return
		}
		rec, exists := st.skus[sku]
		if !exists {
			rec = &skuRec{price: 0}
			st.skus[sku] = rec
		}
		rec.stock += qty
		fmt.Fprintf(out, "ok %s stock=%d\n", sku, rec.stock)

	case "price":
		if n != 3 {
			fail("usage")
			return
		}
		cents, ok := parsePrice(tokens[2])
		if !ok {
			fail("bad price")
			return
		}
		rec, exists := st.skus[tokens[1]]
		if !exists {
			fail("unknown sku " + tokens[1])
			return
		}
		rec.price = cents
		out.WriteString("ok\n")

	case "order":
		if n < 3 {
			fail("usage")
			return
		}
		id := tokens[1]
		if !validOrderID(id) {
			fail("bad order id")
			return
		}
		items := make([]item, 0, n-2)
		for _, tok := range tokens[2:] {
			parts := strings.Split(tok, ":")
			if len(parts) != 2 || !validSku(parts[0]) {
				fail("bad item " + tok)
				return
			}
			qty, ok := parseQty(parts[1])
			if !ok {
				fail("bad item " + tok)
				return
			}
			items = append(items, item{sku: parts[0], qty: qty})
		}
		if _, exists := st.orders[id]; exists {
			fail("order " + id + " already exists")
			return
		}
		seen := make(map[string]bool, len(items))
		for _, it := range items {
			if seen[it.sku] {
				fail("duplicate sku " + it.sku)
				return
			}
			seen[it.sku] = true
			rec, exists := st.skus[it.sku]
			if !exists {
				fail("unknown sku " + it.sku)
				return
			}
			if it.qty > rec.stock {
				fail(fmt.Sprintf("insufficient stock for %s (have %d, need %d)", it.sku, rec.stock, it.qty))
				return
			}
		}
		// All checks passed: reserve stock and price the order.
		var total int64
		for _, it := range items {
			rec := st.skus[it.sku]
			rec.stock -= it.qty
			total += lineCost(it.qty, rec.price)
		}
		st.orders[id] = &order{status: statusPlaced, items: items, total: total}
		fmt.Fprintf(out, "ok %s total=%s\n", id, money(total))

	case "cancel":
		if n != 2 {
			fail("usage")
			return
		}
		o, exists := st.orders[tokens[1]]
		if !exists {
			fail("unknown order " + tokens[1])
			return
		}
		switch o.status {
		case statusPlaced:
			for _, it := range o.items {
				st.skus[it.sku].stock += it.qty
			}
			o.status = statusCancelled
			out.WriteString("ok\n")
		case statusShipped:
			fail("order " + tokens[1] + " already shipped")
		case statusCancelled:
			fail("order " + tokens[1] + " already cancelled")
		}

	case "ship":
		if n != 2 {
			fail("usage")
			return
		}
		o, exists := st.orders[tokens[1]]
		if !exists {
			fail("unknown order " + tokens[1])
			return
		}
		switch o.status {
		case statusPlaced:
			o.status = statusShipped
			out.WriteString("ok\n")
		case statusShipped:
			fail("order " + tokens[1] + " already shipped")
		case statusCancelled:
			fail("order " + tokens[1] + " is cancelled")
		}

	case "report":
		if n != 1 {
			fail("usage")
			return
		}
		reserved := make(map[string]int64)
		var placed, shipped, cancelled int
		var revenue int64
		for _, o := range st.orders {
			switch o.status {
			case statusPlaced:
				placed++
				for _, it := range o.items {
					reserved[it.sku] += it.qty
				}
			case statusShipped:
				shipped++
				revenue += o.total
			case statusCancelled:
				cancelled++
			}
		}
		skus := make([]string, 0, len(st.skus))
		for s := range st.skus {
			skus = append(skus, s)
		}
		sort.Strings(skus)
		for _, s := range skus {
			rec := st.skus[s]
			fmt.Fprintf(out, "%s stock=%d price=%s reserved=%d\n", s, rec.stock, money(rec.price), reserved[s])
		}
		fmt.Fprintf(out, "orders placed=%d shipped=%d cancelled=%d\n", placed, shipped, cancelled)
		fmt.Fprintf(out, "revenue=%s\n", money(revenue))

	default:
		fail("unknown command")
	}
}

func main() {
	st := &store{skus: make(map[string]*skuRec), orders: make(map[string]*order)}
	in := bufio.NewReaderSize(os.Stdin, 1<<16)
	out := bufio.NewWriterSize(os.Stdout, 1<<16)
	defer out.Flush()

	for {
		line, err := in.ReadString('\n')
		if len(line) > 0 || err == nil {
			line = strings.TrimSuffix(line, "\n")
			line = strings.TrimSuffix(line, "\r")
			if strings.Trim(line, " ") != "" {
				st.run(strings.Split(line, " "), out)
			}
		}
		if err != nil {
			if err != io.EOF {
				fmt.Fprintln(os.Stderr, err)
			}
			break
		}
	}
}
