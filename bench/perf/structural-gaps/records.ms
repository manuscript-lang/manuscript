type Particle:
	x: Int
	y: Int
	vx: Int
	vy: Int
	alive: Bool

fn step(var ps: List[Particle]) Unit:
	for i in 0..ps.length():
		if ps[i].alive:
			ps[i].x += ps[i].vx
			ps[i].y += ps[i].vy
			if ps[i].x > 100000 or ps[i].x < 0:
				ps[i].vx = -ps[i].vx

fn energy(ps: List[Particle]) Int:
	var e = 0
	for p in ps:
		if p.alive:
			e += p.vx * p.vx + p.vy * p.vy
	return e

fn main() Unit:
	var ps: List[Particle] = []
	for i in 0..100000:
		ps.append(Particle(i, i * 2 % 1000, i % 7 - 3, i % 5 - 2, i % 9 != 0))
	var t = 0
	for r in 0..200:
		step(var ps)
		t = (t + energy(ps)) % 1000003
	print("{t} {ps[77].x}")
