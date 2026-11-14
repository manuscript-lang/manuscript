import sys
kind,n=sys.argv[1],int(sys.argv[2])
T="\t"
if kind=="nestif":
    s="fn main() Unit:\n\tvar x = 0\n"
    for i in range(n): s+=T*(i+1)+"if x == 0:\n"
    s+=T*(n+1)+"x += 1\n"
    s+=T+'print("{x}")\n'
elif kind=="nestfor":
    s="fn main() Unit:\n\tvar x = 0\n"
    for i in range(n): s+=T*(i+1)+"for i"+str(i)+" in 0..1:\n"
    s+=T*(n+1)+"x += 1\n"
    s+=T+'print("{x}")\n'
elif kind=="nestlist":
    ty="List["*n+"Int"+"]"*n
    s=f"fn main() Unit:\n\tvar x: {ty} = []\n\tprint(\"{{x.length()}}\")\n"
elif kind=="nestclosure":
    s="fn main() Unit:\n\tf := "+"fn: ".join([""]*1)
    s="fn main() Unit:\n"
    s+="\tvar total = 0\n"
    cur=T
    for i in range(n):
        s+=cur+f"g{i} := fn() Int:\n"
        cur+=T
    s+=cur+"return 1\n"
    for i in reversed(range(n)):
        cur=T*(i+1)
        s+=cur+f"return g{i}() + 1\n" if False else ""
    s+="\tprint(\"ok\")\n"
elif kind=="rec":
    s=f"fn f(n: Int) Int:\n\tif n == 0: return 0\n\treturn 1 + f(n - 1)\n\nfn main() Unit:\n\tprint(\"{{f({n})}}\")\n"
elif kind=="nestmatch":
    s="fn main() Unit:\n\tx := 1\n"
    for i in range(n): s+=T*(i+1)+"match x:\n"+T*(i+2)+"1:\n"
    s+=T*(n+2)+'print("deep")\n'
    s+=T*(1)+""
elif kind=="manygen":
    s="".join(f"type B{i}[T]:\n\tv: T\n\n" for i in range(n))
    s+="fn main() Unit:\n"+"".join(f"\tx{i} := B{i}(v: {i})\n" for i in range(n))
    s+="\tprint(\"{x1.v}\")\n"
elif kind=="manyinst":
    s="fn id[T](x: T) T:\n\treturn x\n\nfn main() Unit:\n\tvar t = 0\n"
    s+="".join(f"\tt += id({i})\n\tif id(\"s{i}\").length() > 100: t += 1\n" for i in range(n))
    s+="\tprint(\"{t}\")\n"
print(s,end="")
