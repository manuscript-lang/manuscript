import sys
k=sys.argv[1]; n=int(sys.argv[2])
o=[]
if k=='bigfn':   # one function, n statements
    o.append('fn main() Unit:\n\tvar t = 0\n'+''.join(f'\tt += {i} * (t % 7 + 1)\n\tif t > {i*3}:\n\t\tt -= {i}\n' for i in range(n))+'\tprint(t)\n')
elif k=='locals':
    o.append('fn main() Unit:\n'+''.join(f'\tv{i} := {i} + 1\n' for i in range(n))+'\tprint('+' + '.join(f'v{i}' for i in range(n))+')\n')
elif k=='listlit':
    o.append('fn main() Unit:\n\txs := ['+', '.join(str(i*7%1000) for i in range(n))+']\n\tprint(xs.length())\n')
elif k=='maplit':
    o.append('fn main() Unit:\n\tm: Map[String, Int] := {'+', '.join(f'"key{i}": {i}' for i in range(n))+'}\n\tprint(m.length())\n')
elif k=='match':
    o.append('fn f(x: Int) Int:\n\tmatch x:\n'+''.join(f'\t\t{i}: return {i*2}\n' for i in range(n))+'\t\t_: return -1\n\nfn main() Unit:\n\tprint(f(5))\n')
elif k=='enum':
    o.append('enum E:\n'+''.join(f'\tV{i}(a: Int)\n' for i in range(n))+'\nfn f(e: E) Int:\n\tmatch e:\n'+''.join(f'\t\tV{i}(a): return a + {i}\n' for i in range(n))+'\nfn main() Unit:\n\tprint(f(E.V3(4)))\n')
elif k=='ifchain':
    o.append('fn f(x: Int) Int:\n'+''.join(f'\t{"if" if i==0 else "else if"} x == {i}: return {i}\n' for i in range(n))+'\telse: return -1\n\nfn main() Unit:\n\tprint(f(5))\n')
elif k=='types':
    o.append(''.join(f'type T{i}:\n\ta: Int\n\tb: String\n\nfn mk{i}() T{i}:\n\treturn T{i}({i}, "x")\n\n' for i in range(n))+'fn main() Unit:\n\tprint(mk3().a)\n')
elif k=='concat':
    o.append('fn main() Unit:\n\tx := 5\n\ts := '+' + '.join(f'"p{i}" + x.to_string()' for i in range(n//2))+'\n\tprint(s.length())\n')
elif k=='chain':  # long chain of calls
    o.append(''.join(f'fn g{i}(x: Int) Int:\n\treturn g{i-1}(x) + 1\n\n' if i else 'fn g0(x: Int) Int:\n\treturn x\n\n' for i in range(n))+f'fn main() Unit:\n\tprint(g{n-1}(1))\n')
open(f'{k}_{n}.ms','w').write(''.join(o))
