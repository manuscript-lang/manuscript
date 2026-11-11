export opaque type Approved:
	entity: String
	nonce: String

export opaque type Counter:
	count: Int

export opaque enum Mode:
	Safe
	Wild(level: Int)

fn Approved.label() String:
	return "approved:{self.entity}"

fn var Counter.bump() Unit:
	self.count += 1

fn Counter.value() Int:
	return self.count

export fn approve(entity: String) Approved:
	return Approved(entity: entity, nonce: "n1")

export fn entity(a: Approved) String:
	return a.entity.clone()

export fn counter() Counter:
	return Counter(count: 0)

export fn safe() Mode:
	return Safe

export fn wild(level: Int) Mode:
	return Wild(level)

export fn level(m: Mode) Int:
	match m:
		Safe: return 0
		Wild(level): return level

export fn nonce_of(a: Approved) String:
	return a.nonce.clone()
