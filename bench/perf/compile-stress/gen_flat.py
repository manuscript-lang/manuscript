import sys
kind,n=sys.argv[1],int(sys.argv[2])
out=[]
if kind=="paren":   # deeply nested parens
    out.append("fn main() Unit:\n\tx := "+"("*n+"1"+" + 1)"*n+"\n\tprint(\"{x}\")\n")
elif kind=="chain": # long + chain
    out.append("fn main() Unit:\n\tx := 1"+" + 1"*n+"\n\tprint(\"{x}\")\n")
elif kind=="strchain":
    out.append("fn main() Unit:\n\tx := \"a\""+" + \"b\""*n+"\n\tprint(x.length().to_string())\n")
elif kind=="ifelse":
    s="fn f(x: Int) Int:\n"
    for i in range(n):
        s+="\t"*(i+1)+f"if x == {i}:\n"+"\t"*(i+2)+f"return {i}\n"+"\t"*(i+1)+"else:\n"
    s+="\t"*(n+1)+"return -1\n"
    out.append(s+"fn main() Unit:\n\tprint(\"{f(3)}\")\n")
elif kind=="elseif":
    s="fn f(x: Int) Int:\n\tif x == 0:\n\t\treturn 0\n"
    for i in range(1,n): s+=f"\telse if x == {i}:\n\t\treturn {i}\n"
    s+="\treturn -1\n"
    out.append(s+"fn main() Unit:\n\tprint(\"{f(3)}\")\n")
elif kind=="stmts":
    s="fn main() Unit:\n\tvar x = 0\n"
    for i in range(n): s+=f"\tx += {i}\n"
    s+="\tprint(\"{x}\")\n"
    out.append(s)
elif kind=="funcs":
    s=""
    for i in range(n): s+=f"fn f{i}(x: Int) Int:\n\treturn x + {i}\n\n"
    s+="fn main() Unit:\n\tvar x = 0\n"
    for i in range(0,n,max(1,n//100)): s+=f"\tx = f{i}(x)\n"
    s+="\tprint(\"{x}\")\n"
    out.append(s)
elif kind=="list":
    out.append("fn main() Unit:\n\tx := ["+",".join(str(i) for i in range(n))+"]\n\tprint(\"{x.length()}\")\n")
elif kind=="nestlist":
    out.append("fn main() Unit:\n\tx := "+"["*n+"1"+"]"*n+"\n\tprint(\"ok\")\n")
elif kind=="generic":
    s="type Box[T]:\n\tvalue: T\n\nfn main() Unit:\n\tx := "+"Box("*n+"1"+")"*n+"\n\tprint(\"ok\")\n"
    out.append(s)
elif kind=="closure":
    s="fn main() Unit:\n\tf := "+"fn a: ".join(["" for _ in range(1)])
    s="fn main() Unit:\n\tvar f: fn(Int) Int = fn x: x\n"
    for i in range(n): s+=f"\tf = fn x: x + {i}\n"
    s+="\tprint(\"{f(1)}\")\n"
    out.append(s)
elif kind=="record":
    s="type R:\n"+"".join(f"\tf{i}: Int\n" for i in range(n))+"\nfn main() Unit:\n\tr := R("+", ".join(f"f{i}: {i}" for i in range(n))+")\n\tprint(\"{r.f1}\")\n"
    out.append(s)
elif kind=="enum":
    s="enum E:\n"+"".join(f"\tV{i}\n" for i in range(n))+"\nfn g(e: E) Int:\n\tmatch e:\n"+"".join(f"\t\tE.V{i}: return {i}\n" for i in range(n))+"\nfn main() Unit:\n\tprint(\"{g(E.V1)}\")\n"
    out.append(s)
elif kind=="interp":
    out.append("fn main() Unit:\n\tx := 1\n\tprint(\""+"{x}"*n+"\")\n")
elif kind=="call":
    out.append("fn id(x: Int) Int:\n\treturn x\n\nfn main() Unit:\n\tx := "+"id("*n+"1"+")"*n+"\n\tprint(\"{x}\")\n")
elif kind=="method":
    out.append("fn main() Unit:\n\tx := \"a\""+".trim()"*n+"\n\tprint(x)\n")
print("".join(out),end="")
