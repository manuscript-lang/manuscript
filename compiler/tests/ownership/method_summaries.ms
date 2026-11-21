type Counter:
	count: Int
	label: String

fn Counter.describe() String:
	return f"{self.label}: {self.count}"

fn Counter.named(text: String) Counter:
	return Counter(0, text)

fn Counter.show() String:
	return self.describe()

fn report(c: Counter) String:
	text := c.describe()
	return text

fn Counter.relabel(text: String) Counter:
	return Counter(self.count, text)

fn Counter.pick(other: String) String:
	return other

fn twice(c: Counter, name: String) Int:
	first := c.relabel(name)
	second := c.relabel(name)
	return first.count + second.count

fn borrowed(c: Counter, name: String) String:
	kept := c.pick(name)
	return kept
