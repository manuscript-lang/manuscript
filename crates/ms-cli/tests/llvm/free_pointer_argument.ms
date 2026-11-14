type Rec:
	name: String
	score: Int
	tags: List[String]
	next: Rec?

fn cmp_rec(a: Rec, b: Rec) Int:
	if a.score != b.score:
		if a.score < b.score: return -1
		return 1
	return a.name.compare(b.name)

fn find_first(xs: List[Rec], min_score: Int) Rec?:
	for r in xs:
		if r.score >= min_score: return r.clone()
	return none

fn main() Int:
	var rs585617: List[Rec] = []
	rs585617.append(Rec("a,b,c", 1, [], none))
	sorted585617 := rs585617.sorted(cmp_rec)
	for q in sorted585617:
		print("{q.name}:{q.score}")
	f585617 := find_first(rs585617, -2)
	if hit := f585617:
		print("hit {hit.name}")
	return 0
