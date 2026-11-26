import (
	panic from "@std/core.ms",
	stdin from "@std/io/io.ms",
	lines from "@std/io/steps.ms",
	collect from "@std/io/streams.ms",
)

type Item {
	sku String
	qty Int
}

type Order {
	items List[Item]
	status String
	total Int
}

type Warehouse {
	stock Map[String, Int]
	price Map[String, Int]
	orders Map[String, Order]
}

fn money(
	c Int
) String => return f"{c / 100}.{if c % 100 < 10 { "0" } else { "" }}{c % 100}"

fn valid_sku(s String) Bool => return (
	not s.is_empty()
	and s.scalar_values().all(
		c => ((c >= 65 and c <= 90) or (c >= 48 and c <= 57) or c == 45)
	)
)

fn valid_oid(s String) Bool => return (
	not s.is_empty()
	and s.scalar_values().all(
		c => ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 45)
	)
)

// 1 to 7 ASCII digits within lo..hi.
fn number(s String, lo, hi Int) Int? {
	if (
		s.length() < 1
		or s.length() > 7
		or not s.scalar_values().all(c => (c >= 48 and c <= 57))
	) { return null }

	n := s.parse_int() or panic("called Optional.get() on null")
	return if n >= lo and n <= hi { n } else { null }
}

fn place_order(var w Warehouse, t List[String]) String {
	id := t[1]
	if not valid_oid(id) { return "error: bad order id" }
	if w.orders.contains(
		id
	) { return f"error: order {id} already exists" }

	var items = List[Item]()

	for token in t.slice(2, t.length()).get() {
		p := token.split(":").collect()
		if (
			p.length() != 2
			or not valid_sku(p[0])
			or not (number(p[1], 1, 100000) != null)
		) { return f"error: bad item {token}" }

		items.append(
			Item(
				p[0].clone(),
				number(p[1], 1, 100000) or panic(
					"called Optional.get() on null"
				),
			)
		)
	}

	var seen = Set[String]()

	for it in items {
		if seen.contains(
			it.sku
		) { return f"error: duplicate sku {it.sku}" }

		have := w.stock.get(it.sku) or (-1)
		if have < 0 { return f"error: unknown sku {it.sku}" }
		if it.qty > have { return f"error: insufficient stock for {it.sku} (have {have}, need {it.qty})" }

		seen.add(it.sku.clone())
	}

	var total = 0

	for it in items {
		w.stock[it.sku.clone()] = (
			(w.stock.get(it.sku) or panic("called Optional.get() on null"))
			- it.qty
		)
		total += (
			if it.qty >= 10 {
				(
					it.qty * (
						w.price.get(it.sku)
						or panic(
							"called Optional.get() on null"
						)
					) * 90
					+ 50
				) / 100
			} else {
				it.qty * (w.price.get(it.sku) or panic("called Optional.get() on null"))
			}
		)
	}

	w.orders[id.clone()] = Order(items, "placed", total)
	return f"ok {id} total={money(total)}"
}

fn report(w Warehouse) String {
	var reserved = Map[String, Int]()
	orders := w.orders.values()
	for o in orders.filter(o => o.status == "placed") {
		for it in o.items {
			reserved[it.sku.clone()] = (reserved.get_or(it.sku, 0) + it.qty)
		}
	}

	count := fn(s String) Int => orders.count(o => o.status == s)
	rows := w.stock.keys().sorted((a, b) => a.compare(b)).map(
		k => f"{k} stock={(w.stock.get(k) or panic("called Optional.get() on null"))} price={money(w.price.get(k) or panic("called Optional.get() on null"))} reserved={reserved.get_or(k, 0)}"
	)
	revenue := orders.filter(o => o.status == "shipped").map(o => o.total).sum()
	return f"{rows.join("\n")}{if rows.is_empty() { "" } else { "\n" }}orders placed={count("placed")} shipped={count("shipped")} cancelled={count("cancelled")}\nrevenue={money(revenue)}"
}

fn run_command(var w Warehouse, line String) String {
	t := line.split(" ").collect()
	name := t[0]
	arity := (
		{"stock": 3, "price": 3, "cancel": 2, "ship": 2, "report": 1}.get(name)
		or 0
	)
	if arity == 0 and name != "order" { return "error: unknown command" }
	if (if name == "order" { t.length() < 3 } else { t.length() != arity }) { return "error: usage" }
	if name == "order" { return place_order(w, t) }
	if name == "report" { return report(w) }

	if name == "stock" {
		if not valid_sku(t[1]) { return "error: bad sku" }
		if not (number(t[2], 1, 100000) != null) { return "error: bad quantity" }

		now := (
			w.stock.get_or(t[1], 0)
			+ (
				number(t[2], 1, 100000)
				or panic("called Optional.get() on null")
			)
		)
		w.stock[t[1].clone()] = now
		w.price.add_default(t[1].clone(), 0)
		return f"ok {t[1]} stock={now}"
	}

	if name == "price" {
		if not (number(t[2], 0, 10000000) != null) { return "error: bad price" }
		if not w.stock.contains(t[1]) { return f"error: unknown sku {t[1]}" }

		w.price[t[1].clone()] = (
			number(t[2], 0, 10000000)
			or panic("called Optional.get() on null")
		)
		return "ok"
	}

	if not w.orders.contains(t[1]) { return f"error: unknown order {t[1]}" }

	var o = (w.orders.get(t[1]) or panic("called Optional.get() on null")).clone()

	if name == "cancel" {
		if o.status != "placed" { return f"error: order {t[1]} already {o.status}" }

		for it in o.items {
			w.stock[it.sku.clone()] = (
				(
					w.stock.get(it.sku)
					or panic("called Optional.get() on null")
				)
				+ it.qty
			)
		}
		o.status = "cancelled"
	} else {
		if o.status != "placed" { return f"error: order {t[1]} {if o.status == "shipped" { "already shipped" } else { "is cancelled" }}" }

		o.status = "shipped"
	}

	w.orders[t[1].clone()] = o
	return "ok"
}

fn main() Void {
	var w = Warehouse(Map[String, Int](), Map[String, Int](), Map[String, Order]())
	if ls := stdin() | lines | collect(null) {
		for l in ls.filter(l => not l.replace(" ", "").is_empty()) {
			print(run_command(w, l))
		}
	}
}
