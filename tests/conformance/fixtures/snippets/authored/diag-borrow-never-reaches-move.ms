// conform: tags=diagnostics,ownership,tier-core
// conform: phase=check
// conform: origin=design/proposals/borrowed-fields-and-looks.md
type Item {
	name String
}

type View {
	item &Item
}

fn hold Item.label() &String {
	return self.name
}

fn take_text(move text String) Int {
	return text.length()
}

fn take_item(move item Item) Int {
	return item.name.length()
}

fn through_param(text String) Int {
	return take_text(text)
}

fn through_field(view View) Int {
	return take_item(view.item)
}

fn through_local(item Item) Int {
	view := View(item)
	return take_item(view.item)
}

fn main() Void {
	item := Item("a")
	print(through_param(item.label()))
	print(through_field(View(item)))
	print(through_local(item))
}
