import sys
n=int(sys.argv[1])
ms=['type P:\n\tx: Int\n\tname: String\n']
rs=['use std::collections::HashMap;\nstruct P { x: i64, name: String }\n']
go=['package main\nimport ("fmt")\ntype P struct { x int; name string }\n']
for i in range(n):
    ms.append(f'''fn f{i}(a: Int) Int:
	var m: Map[Int, Int] = {{}}
	var t = 0
	for k in 0..(a % 7 + 3):
		m[k * {i+1}] = k + a
		t += m[k * {i+1}] % {i%11+2}
	p := P(t, "item-{i}-{{a}}")
	if p.name.length() > {i%9+5}:
		t += p.x
	else:
		t -= p.name.length()
	var xs: List[Int] = []
	for j in 0..4:
		xs.append(j * {i%5+1} + t)
	return t + xs[a % 4]
''')
    rs.append(f'''fn f{i}(a: i64) -> i64 {{
    let mut m: HashMap<i64, i64> = HashMap::new();
    let mut t = 0i64;
    for k in 0..(a % 7 + 3) {{ m.insert(k * {i+1}, k + a); t += m[&(k * {i+1})] % {i%11+2}; }}
    let p = P {{ x: t, name: format!("item-{i}-{{}}", a) }};
    if p.name.len() as i64 > {i%9+5} {{ t += p.x; }} else {{ t -= p.name.len() as i64; }}
    let mut xs: Vec<i64> = Vec::new();
    for j in 0..4 {{ xs.push(j * {i%5+1} + t); }}
    t + xs[(a % 4) as usize]
}}
''')
    go.append(f'''func f{i}(a int) int {{
	m := map[int]int{{}}
	t := 0
	for k := 0; k < a%7+3; k++ {{ m[k*{i+1}] = k + a; t += m[k*{i+1}] % {i%11+2} }}
	p := P{{t, fmt.Sprintf("item-{i}-%d", a)}}
	if len(p.name) > {i%9+5} {{ t += p.x }} else {{ t -= len(p.name) }}
	xs := []int{{}}
	for j := 0; j < 4; j++ {{ xs = append(xs, j*{i%5+1}+t) }}
	return t + xs[a%4]
}}
''')
ms.append('fn main() Unit:\n\tvar s = 0\n'+''.join(f'\ts += f{i}({i})\n' for i in range(n))+'\tprint(s)\n')
rs.append('fn main() {\n    let mut s = 0i64;\n'+''.join(f'    s += f{i}({i});\n' for i in range(n))+'    println!("{}", s);\n}\n')
go.append('func main() {\n\ts := 0\n'+''.join(f'\ts += f{i}({i})\n' for i in range(n))+'\tfmt.Println(s)\n}\n')
open(f'p{n}.ms','w').write('\n'.join(ms)); open(f'p{n}.rs','w').write('\n'.join(rs)); open(f'p{n}.go','w').write('\n'.join(go))
