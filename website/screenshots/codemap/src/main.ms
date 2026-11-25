import expect_equal from "@std/test/test.ms"

MAX_QUANTITY := 10000

type Order {
	id, sku String
	count Int
}

type Warehouse {
	stock Map[String, Int]
	price Map[String, Int]
	orders List[Order]
}

fn is_sku_char(c Int) Bool => (c >= 65 and c <= 90) or (c >= 48 and c <= 57)

fn is_oid_char(c Int) Bool => is_sku_char(c) or c == 45

fn valid_sku(sku String) Bool {
	return (
		sku.length() >= 1
		and sku.length() <= 8
		and sku.scalar_values().all(is_sku_char)
	)
}

fn valid_oid(id String) Bool {
	return id.length() >= 1 and id.scalar_values().all(is_oid_char)
}

fn arity(name String) Int {
	match name {
		"stock" => return 3
		"price" => return 3
		"order" => return 4
		"report" => return 1
		_ => return 0
	}
}

fn number(s String) Int? => s.parse_int()

fn quantity(s String) Int? {
	n := number(s)
	if n == null {
		return null
	}

	return if n >= 1 and n <= MAX_QUANTITY { n } else { null }
}

fn money(cents Int) String => f"{cents / 100}.{cents % 100}"

fn place_order(var w Warehouse, id, sku String, count Int) String {
	if not valid_oid(id) {
		return "error: bad order id"
	}

	now := w.stock.get_or(sku, 0)
	if now < count {
		return f"error: only {now} of {sku} in stock"
	}

	w.stock.add(sku.clone(), now - count)
	w.orders.append(Order(id.clone(), sku.clone(), count))
	return f"ok {id}"
}

fn report(w Warehouse) String => f"{w.orders.length()} orders"

fn run_command(var w Warehouse, line String) String {
	t := line.split(" ")
	name := t[0]
	want := arity(name)
	if want == 0 {
		return "error: unknown command"
	}
	if t.length() != want {
		return "error: usage"
	}

	if name == "stock" {
		sku := t[1]
		if not valid_sku(sku) {
			return "error: bad sku"
		}

		q := quantity(t[2])
		if q == null {
			return "error: bad quantity"
		}

		w.stock.add(sku.clone(), w.stock.get_or(sku, 0) + q)
		return f"ok {sku}"
	}

	if name == "order" {
		q := quantity(t[3])
		if q == null {
			return "error: bad quantity"
		}

		return place_order(w, t[1], t[2], q)
	}

	return report(w)
}

fn run(lines List[String]) List[String] {
	var w = Warehouse(Map[String, Int](), Map[String, Int](), List[Order]())
	return lines.map(line => run_command(w, line))
}

fn main() Void {
	for line in run(["stock AB 5", "order O-1 AB 2", "report"]) {
		print(line)
	}
}

test "an order draws stock down" {
	out := run(["stock AB 5", "order O-1 AB 2", "report"])
	expect_equal(out[1], "ok O-1")?
}
