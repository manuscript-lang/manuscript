"""Generator for c59-spreadsheet. The expected outputs come from the Go oracle in oracle/*.ref (built with the local
Go toolchain); this script only supplies the inputs. Deterministic; run: python3 gen.py"""
import json, pathlib, shutil, subprocess, sys, tempfile

root = pathlib.Path(__file__).parent

def build_oracle():
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="msbench-oracle-"))
    for f in sorted((root / "oracle").glob("*.ref")):
        shutil.copy(f, tmp / f.name[:-4])
    (tmp / "go.mod").write_text("module oracle\n\ngo 1.21\n")
    subprocess.run(["go", "build", "-o", "oracle", "."], cwd=tmp, check=True)
    return tmp / "oracle"

ORACLE = build_oracle()

def solve(stdin):
    r = subprocess.run([str(ORACLE)], input=stdin, capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        sys.exit("oracle failed (exit %d): %s" % (r.returncode, r.stderr[:500]))
    return r.stdout

def case(name, stdin): return {"name": name, "stdin": stdin, "stdout": solve(stdin)}

def write_cases(examples, hidden):
    names = [c["name"] for c in hidden]
    assert len(set(names)) == len(names), "duplicate case names"
    for d, cs in (("examples", examples), ("hidden", hidden)):
        (root / d).mkdir(exist_ok=True)
        (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
    print(len(examples), len(hidden))

CASES = []
def add(name, script):
    CASES.append(case(name, script.strip("\n") + "\n"))

def sets(pairs):
    return "".join("set %s %s\n" % (k, v) for k, v in pairs)

add("value-types", """
set A1 42
set A2 -3.5
set A3 1e3
set A4 .5
set A5 +7
set A6 TRUE
set A7 false
set A8 hello world
set A9 '123
set A10 '=not a formula
set A11   spaced   out  
set A12 1,5
set A13 0x10
set A14 12abc
set A15 -0
set A16 1e400
set A17 007
get A1
get A2
get A3
get A4
get A5
get A6
get A7
get A8
get A9
get A10
get A11
get A12
get A13
get A14
get A15
get A16
get A17
get B1
show A9
show A10
show A11
show A6
show B1
print
""")
add("number-formatting", sets([("A1", "=1/3"), ("A2", "=2/3"), ("A3", "=0.1+0.2"), ("A4", "=1e15"), ("A5", "=123456789.123456789"), ("A6", "=1e-11"), ("A7", "=-1/3"), ("A8", "=1000000*1000000"), ("A9", "=5e-10"), ("A10", "=0.00000000005"), ("A11", "=100/3"), ("A12", "=2^0.5"), ("A13", "=-0"), ("A14", "=0*-1")]) + "".join("get A%d\n" % i for i in range(1, 15)) + "print A1:A14\n")
add("clear-and-overwrite", """
set A1 5
set A2 =A1*2
get A2
clear A1
get A1
get A2
set A1 text
get A2
set A2 99
show A2
clear A2
get A2
clear A2
show A2
set A3
get A3
set A4    
stats
""")
add("operator-precedence", """
set A1 =1+2*3
set A2 =(1+2)*3
set A3 =-2^2
set A4 =2^3^2
set A5 =2^-1
set A6 =-(2+3)*2
set A7 =10-4-3
set A8 =100/10/5
set A9 =2*3^2
set A10 =--5
set A11 =+-+3
set A12 ="a"&1+2&"b"
set A13 =1+1=2
set A14 =1<2=TRUE
set A15 =3>2<>FALSE
set A16 =2^2*3
set A17 =1&2=12
set A18 =-2^-2
set A19 =7-+2
set A20 =(((1)))
print A1:A20
""")
add("coercions", """
set A1 5
set B1 "5"
set A2 =A1+"3"
set A3 ="3"*"4"
set A4 =TRUE+TRUE
set A5 =C1+5
set A6 =C1&"x"
set A7 ="abc"+1
set A8 =""+1
set A9 =" 12 "+1
set A10 ="1e2"+0
set A11 =FALSE*5
set A12 =-"5"
set A13 =-"x"
set A14 =C1*C2
set A15 =A5&A6&TRUE&1.50
print A1:A15
""")
add("comparisons", """
set A1 5
set A2 apple
set A3 Apple
set A4 TRUE
set B1 =A1=5
set B2 =A1<>5
set B3 =A2="apple"
set B4 =A2=A3
set B5 =A2<A3
set B6 =A1<A2
set B7 =A2<A4
set B8 =A1<A4
set B9 =C1=0
set B10 =C1=""
set B11 =C1=C2
set B12 =C1<1
set B13 =A4=TRUE
set B14 =A4>FALSE
set B15 ="a"<"b"
set B16 ="B"<"a"
set B17 ="10"<"9"
set B18 =10<9
set B19 =C1=FALSE
set B20 =A1>=5
set B21 =A1<=4
print B1:B21
""")
add("errors-basic", """
set A1 =1/0
set A2 =A1+1
set A3 =nosuch(1)
set A4 =B9+nosuch
set A5 =A1
set A6 =A3&A1
set A7 =A1+A3
set A8 =A3+A1
set A9 =IFERROR(A1,"ok")
set A10 =ISERROR(A2)
set A11 =ISERROR(5)
set A12 =IF(A1,1,2)
set A13 =SUM(A1,A3)
set A14 =SUM(A3,A1)
set A15 =AAA1
set A16 =A1000
set A17 =#REF!
set A18 =SUM(#REF!,1)
set A19 =A1:A2
set A20 =1+A1:A2
set A21 =SQRT(-1)
set A22 =0^-1
set A23 =10^400
set A24 =MOD(1,0)
set A25 =ABS(A1:A2)
print A1:A25
""")
add("errors-parse", """
set A1 =
set A2 =1+
set A3 =(1
set A4 =1)
set A5 =1 2
set A6 =@
set A7 ="abc
set A8 =SUM(1,)
set A9 =SUM(,1)
set A10 =1..2
set A11 =A1 A2
set A12 =*3
set A13 =SUM(1
set A14 =$
set A15 =1+#X
set A16 =A1 B1
set A17 = 1 + 2 
set A18 =sum( 1 , 2 )
set A19 =SUM()
set A20 =IF()
print A1:A20
show A2
get A2
set A2 =1+1
get A2
stats
""")
add("sum-avg-min-max", """
set A1 1
set A2 text
set A3 TRUE
set A4 4
set A6 6
set B1 =SUM(A1:A6)
set B2 =AVERAGE(A1:A6)
set B3 =MIN(A1:A6)
set B4 =MAX(A1:A6)
set B5 =COUNT(A1:A6)
set B6 =COUNTA(A1:A6)
set B7 =SUM(A1,A4,10)
set B8 =SUM(A1:A6,100)
set B9 =SUM("5",TRUE,A1)
set B10 =SUM("x")
set B11 =AVERAGE(C1:C5)
set B12 =MIN(C1:C5)
set B13 =MAX(C1:C5,-3)
set B14 =PRODUCT(A1,A4,A6)
set B15 =PRODUCT(C1:C3)
set B16 =MEDIAN(A1,A4,A6)
set B17 =MEDIAN(1,2,3,4)
set B18 =MEDIAN(C1:C2)
set B19 =SUM(A1:A6,B1)
set B20 =COUNT(A1,"3",TRUE,A2)
set B21 =COUNTA(C1:C3)
set B22 =SUM(B1:B20)
set B23 =AVERAGE(A1,A4)
set B24 =SUM(A6:A1)
set B25 =SUM(A1:A1)
print B1:B25
""")
add("aggregate-errors-in-range", """
set A1 1
set A2 =1/0
set A3 =nosuch()
set A4 3
set B1 =SUM(A1:A4)
set B2 =SUM(A3:A4)
set B3 =COUNT(A1:A4)
set B4 =COUNTA(A1:A4)
set B5 =MAX(A1:A4)
set B6 =AVERAGE(A4:A1)
set B7 =IFERROR(SUM(A1:A4),-1)
set B8 =CONCAT(A1:A4)
set B9 =AND(A1:A4)
set B10 =COUNTIF(A1:A4,">0")
print B1:B10
""")
add("logic-functions", """
set A1 =IF(TRUE,"y","n")
set A2 =IF(0,"y","n")
set A3 =IF(2,"y")
set A4 =IF(FALSE,"y")
set A5 =IF("true",1,2)
set A6 =IF("maybe",1,2)
set A7 =IF(C1,1,2)
set A8 =IF(TRUE,1,1/0)
set A9 =IF(FALSE,1/0,2)
set A10 =IF(TRUE,A1:A2,0)
set A11 =AND(TRUE,1,"true")
set A12 =AND(TRUE,FALSE,1/0)
set A13 =OR(FALSE,0,"false")
set A14 =OR(1/0,TRUE)
set A15 =AND()
set A16 =NOT(0)
set A17 =NOT("x")
set A18 =NOT(C1)
set A19 =AND(C1:C3)
set A20 =OR(B1:B2,TRUE)
set B1 text
set B2 5
set A21 =OR(B1:B2)
set A22 =AND(B1:B2)
set A23 =CHOOSE(2,"a","b","c")
set A24 =CHOOSE(4,"a","b","c")
set A25 =CHOOSE(1,1/0,2)
set A26 =CHOOSE(0,1)
set A27 =CHOOSE(2.9,10,20,30)
set A28 =IFERROR(1/0,IFERROR(nosuch(),"deep"))
set A29 =IFERROR(5,1/0)
print A1:A28
get A29
""")
add("text-functions", """
set A1 Hello World
set A2 =LEN(A1)
set A3 =UPPER(A1)
set A4 =LOWER(A1)
set A5 =LEFT(A1)
set A6 =LEFT(A1,5)
set A7 =RIGHT(A1,5)
set A8 =RIGHT(A1)
set A9 =MID(A1,7,3)
set A10 =MID(A1,7,100)
set A11 =MID(A1,50,3)
set A12 =LEFT(A1,100)
set A13 =LEFT(A1,0)
set A14 =LEFT(A1,-1)
set A15 =MID(A1,0,1)
set A16 =TRIM("  a   b  c  ")
set A17 =CONCAT("a",1,TRUE,C1,"b")
set A18 =CONCAT(A2:A4)
set A19 =SUBSTITUTE(A1,"o","0")
set A20 =SUBSTITUTE(A1,"","x")
set A21 =SUBSTITUTE(A1,"World","")
set A22 =LEN(12345)
set A23 =LEN(C1)
set A24 =VALUE("3.5")
set A25 =VALUE("abc")
set A26 =VALUE(TRUE)
set A27 =VALUE(" 7 ")
set A28 =LEFT(1234,2)+1
set A29 =UPPER(A1:A2)
set A30 =LEN()
print A1:A30
""")
add("math-functions", """
set A1 =ROUND(2.5)
set A2 =ROUND(-2.5)
set A3 =ROUND(1.2345,2)
set A4 =ROUND(1234.5678,-2)
set A5 =ROUND(0.5,0)
set A6 =ROUND(1.005,2)
set A7 =ROUND(2.675,2)
set A8 =ROUND(5,20)
set A9 =INT(-1.5)
set A10 =INT(1.9)
set A11 =ABS(-4.25)
set A12 =SQRT(16)
set A13 =SQRT(2)
set A14 =POW(2,10)
set A15 =POW(-8,1/3)
set A16 =MOD(10,3)
set A17 =MOD(-10,3)
set A18 =MOD(10,-3)
set A19 =MOD(5.5,2)
set A20 =MOD(-1,5)
set A21 =ABS("x")
set A22 =ROUND(1.5,1.9)
set A23 =INT(-0.5)
set A24 =POW(0,0)
set A25 =POW(2,0.5)
print A1:A25
""")
add("info-functions", """
set A1 5
set A2 text
set B1 =ISBLANK(A1)
set B2 =ISBLANK(C5)
set B3 =ISNUMBER(A1)
set B4 =ISNUMBER(A2)
set B5 =ISTEXT(A2)
set B6 =ISTEXT(A1)
set B7 =ISNUMBER("5")
set B8 =ISBLANK("")
set B9 =ROW(C7)
set B10 =COLUMN(C7)
set B11 =ROW(B3:D9)
set B12 =COLUMN(B3:D9)
set B13 =ROW(5)
set B14 =ROW(AA1)
set B15 =ISNUMBER(1/0)
set B16 =ISERROR(nosuch())
set B17 =ROW(B17)
print B1:B17
dependents B17
precedents B17
""")
add("index-function", """
set A1 1
set B1 2
set C1 3
set A2 4
set B2 5
set C2 6
set E1 =INDEX(A1:C2,2,3)
set E2 =INDEX(A1:C2,1,1)
set E3 =INDEX(A1:C2,3,1)
set E4 =INDEX(A1:C2,1,4)
set E5 =INDEX(A1:C1,2)
set E6 =INDEX(A1:A2,2)
set E7 =INDEX(A1:C2,0,1)
set E8 =INDEX(A1,1)
set E9 =INDEX(A2:C2,3)
set E10 =INDEX(A1:C2,2.9,1.9)
print E1:E10
""")
add("countif", """
set A1 5
set A2 10
set A3 apple
set A4 Apple
set A5 TRUE
set A6 15
set A7 banana
set B1 =COUNTIF(A1:A7,10)
set B2 =COUNTIF(A1:A7,">5")
set B3 =COUNTIF(A1:A7,">=10")
set B4 =COUNTIF(A1:A7,"<10")
set B5 =COUNTIF(A1:A7,"<>10")
set B6 =COUNTIF(A1:A7,"apple")
set B7 =COUNTIF(A1:A7,"=apple")
set B8 =COUNTIF(A1:A7,"<>apple")
set B9 =COUNTIF(A1:A8,"b")
set B10 =COUNTIF(A1:A7,TRUE)
set B11 =COUNTIF(A1:A7,">a")
set B12 =COUNTIF(A1:A7,"")
set B13 =COUNTIF(A1:A7,"5")
set B14 =COUNTIF(A1:A7,A6)
set B15 =COUNTIF(A1,5)
set B16 =COUNTIF(5,5)
print B1:B16
""")
add("dependency-chain-recalc", """
set A1 1
set A2 =A1+1
set A3 =A2+1
set A4 =A3+1
set A5 =A4+1
stats
set A1 10
set A1 10
set A3 100
set A5 =A1
stats
clear A2
get A4
stats
show A4
dependents A1
dependents A2
precedents A4
""")
add("dependency-diamond-and-ranges", """
set A1 1
set B1 =A1*2
set B2 =A1*3
set C1 =B1+B2
set C2 =SUM(A1:B2)
set C3 =SUM(B1:B2)+C1
set D1 =C3
stats
set A1 2
stats
set B2 5
stats
set Z9 7
stats
set A2 9
stats
print A1:D3
dependents A1
dependents B2
precedents C2
precedents C3
precedents D1
""")
add("recalc-counts-unchanged-value", """
set A1 5
set A2 =A1*0
set A3 =A2+1
set A4 =A3
set A1 6
set A1 6
set A1 text
set A1 =1
stats
""")
add("range-dependency-empty-cells", """
set B1 =SUM(A1:A3)
get B1
set A2 4
get B1
set A3 =A2*2
get B1
clear A2
get B1
dependents A2
dependents A3
precedents B1
set B2 =SUM(A3:A1)
precedents B2
set B3 =COUNT(C1:E3)
precedents B3
stats
""")
add("cycles-basic", """
set A1 =A1
get A1
set B1 =B2
set B2 =B1
get B1
get B2
set C1 =B1+1
get C1
set D1 =IFERROR(B1,"safe")
get D1
set B2 5
get B1
get C1
get D1
set A1 =1
get A1
stats
""")
add("cycles-three-and-range", """
set A1 =A2+1
set A2 =A3+1
set A3 =A1+1
get A1
get A2
get A3
set B1 =SUM(A1:A3)
get B1
set C1 =SUM(C1:C3)
get C1
set D1 =D2
set D2 =D3
set D3 =5
get D1
set D3 =D1
get D1
get D3
set D3 0
get D1
set E1 =IF(TRUE,1,E1)
get E1
set E2 =ROW(E2)
get E2
set A2 7
get A1
get A3
get B1
print A1:E3
""")
add("cycles-break-and-reform", """
set A1 =B1
set B1 =C1
set C1 =A1
set D1 =A1&"?"
set E1 =IFERROR(D1,"err")
show D1
get E1
set C1 1
get A1
get B1
get C1
get D1
get E1
set C1 =A1
get E1
set C1 =D1
get E1
dependents A1
stats
""")
add("cycle-with-outside-formula", """
set A1 =B1+C1
set B1 =A1+1
set C1 =10
set D1 =A1+B1+C1
set E1 =IFERROR(A1,0)+1
get A1
get B1
get D1
get E1
set B1 5
get A1
get B1
get D1
get E1
""")
add("copy-relative-absolute", """
set A1 1
set A2 2
set A3 3
set B1 =A1*2
set B2 =$A1+A$1
set B3 =$A$1+A1
set C1 =SUM(A1:A3)
set C2 =SUM($A1:A$3)
set C3 =SUM($A$1:$A$3)
copy B1 D1
copy B2 D2:D3
copy B3 E3
copy C1 F1:G2
copy C2 H5
copy C3 I5:J6
show D1
show D2
show D3
show E3
show F1
show G2
show H5
show I5
show J6
print D1:J6
""")
add("copy-out-of-range-and-strings", """
set B2 =A1+"A1"&A1
set C3 =SUM(A1:B2)&" A1"
set D4 =Z999+A1
copy B2 A1
show A1
get A1
copy C3 A1:B2
show A1
show B1
show A2
show B2
copy D4 E5
show E5
get E5
copy D4 C3
show C3
copy D4 A1
show A1
""")
add("copy-constants-and-empty", """
set A1 hello
set A2 5
set A3 =A2
copy A1 B1:B3
copy A2 C1:C2
copy Z9 A1
get A1
copy A3 B3
copy A3 A3
show A3
get B3
print A1:C3
dependents A2
""")
add("copy-chain-incremental", """
set A1 1
set A2 =A1+1
copy A2 A3:A200
get A200
stats
set A1 100
get A200
stats
set A100 =0
get A200
stats
dependents A198
precedents A200
""")
add("csv-import-export", """
import A1
name,qty,price,total
apple,3,1.5,=B2*C2
"pear, ripe",2,2.25,=B3*C3
banana,12,0.25,=B4*C4
total,=SUM(B2:B4),,=SUM(D2:D4)
.
print
export
export formulas
export A1:B2
export formulas C2:D3
get D5
set B2 10
export D1:D5
""")
add("csv-quoting-roundtrip", '''
set A1 plain
set A2 "He said ""hi"""
set A3 a,b
set A4 ' leading space
set A5 trailing space 
set A6 =CONCAT("x",",","y")
set A7 line1
set A8 =""
set A9 ="q""q"
export
export formulas
import C1
"multi
line","quoted ""x""",,end
a,b
.
get C1
get D1
get E1
get F1
print C1:F2
''')
add("csv-import-types", """
import B2
1,2.5,abc,TRUE,false
'007,=A1,=B2+C2, spaced ,"quoted number"
,,,,
"=1+1",x
.
print A1:F5
stats
set B3 =SUM(B2:D2)
import B3
7,8
.
get B3
dependents B3
""")
add("csv-import-overwrite-and-clear", """
set A1 1
set A2 2
set A3 =A1+A2
set A4 =A3*2
import A1
,10

5
.
print A1:C4
stats
get A4
""")
add("csv-import-range-errors", """
import Z999
1,2
.
get Z999
import Z1
1,2
.
import A999
1
2
.
get A999
import A1
.
import
import A0
x
.
import AA1
x
.
stats
""")
add("print-and-export-ranges", """
set A1 1
set B2 hello
set C3 =A1+1
print
print B2:C3
print C3:B2
print A1
print Z1:Z2
export B2:B2
print A1:
print 1A
print A1 B2
export formulas A1:C3
print formulas
export values B2:C3
export
""")
add("command-errors", """
frobnicate
set
set A1
set AA1 5
set A0 5
set A1000 5
set a1 7
get a1
get
get A1 B1
get 11
show
clear
clear A1 A2
precedents
dependents A1 A2
stats extra
copy A1
copy A1 B1 C1
copy A1 ZZ
copy 1 A1
precedents Q
""")
add("case-insensitive", """
set a1 5
set b2 =sum(A1:a1)+Sum(a1)
set c3 =If(true,"Y","N")
set d4 =b2&c3
print A1:D4
show B2
get b2
copy b2 e5
show E5
""")
add("whitespace-and-formula-text", """
set A1    =  1 +   2  
show A1
set A2 =SUM( A1 ,  2 )
show A2
set A3 = 5
get A3
show A3
set A4 ="  keep  "
get A4
set A5 text with   inner   spaces
show A5
""")
add("budget-scenario", """
import A1
item,jan,feb,mar,total
rent,1200,1200,1200,=SUM(B2:D2)
food,300,320.5,298.75,=SUM(B3:D3)
fun,100,80,150,=SUM(B4:D4)
total,=SUM(B2:B4),=SUM(C2:C4),=SUM(D2:D4),=SUM(E2:E4)
avg,=AVERAGE(B2:B4),=AVERAGE(C2:C4),=AVERAGE(D2:D4),=AVERAGE(E2:E4)
max,=MAX(B2:B4),=MAX(C2:C4),=MAX(D2:D4),=MAX(E2:E4)
.
print
stats
set C3 400
get E5
get F5
set F1 over
set F2 =IF(E2>3500,"over","ok")
copy F2 F3:F4
print E1:F4
set B2 =B2
get B2
get E2
stats
""")
add("grade-book", """
import A1
student,hw1,hw2,exam,avg,grade
ann,90,80,70,,
bob,60,,95,,
cy,100,100,100,,
.
set E2 =AVERAGE(B2:D2)
copy E2 E3:E4
set F2 =IF(E2>=90,"A",IF(E2>=80,"B",IF(E2>=70,"C","F")))
copy F2 F3:F4
print
set C3 75
print E1:F4
set G1 =COUNTIF(F2:F4,"A")
get G1
set G2 =COUNTIF(E2:E4,">=80")
get G2
stats
""")
add("loan-table", """
set A1 principal
set B1 10000
set A2 rate
set B2 0.05
set A3 months
set B3 12
set A4 payment
set B4 =ROUND(B1*(B2/12)/(1-POW(1+B2/12,-B3)),2)
set A6 month
set B6 balance
set C6 interest
set D6 principal
set B7 =B1
set C7 =ROUND(B7*$B$2/12,2)
set D7 =$B$4-C7
set A7 1
set A8 =A7+1
set B8 =ROUND(B7-D7,2)
copy B8 B9:B18
copy C7 C8:C18
copy D7 D8:D18
copy A8 A9:A18
get B4
print A6:D18
get B18
set B1 20000
get B4
get B18
stats
""")
add("gradual-big-grid", """
set A1 1
set B1 =A1+1
copy B1 C1:Z1
copy A1 A2:A60
set A2 =A1+1
copy A2 A3:A60
copy B1 B2:Z60
get Z60
get A60
stats
set A1 2
get Z60
stats
set N30 =0
get Z60
stats
""")
add("sum-of-totals-dependents", """
set A1 =B1+C1
set A2 =B2+C2
set A3 =SUM(A1:A2)
set B1 1
set C1 2
set B2 3
set C2 4
get A3
dependents B1
dependents C2
dependents A1
set B1 =A3
get A1
get A3
dependents B1
""")

add("formula-literals", '''
set A1 =1.5E3
set A2 =.5+.5
set A3 =1.+1
set A4 =1e2+1E-2
set A5 ="say ""hi"""
set A6 =""""
set A7 =LEN(A6)
set A8 =" a "&"b"
set A9 =1E
set A10 =2e+3
set A11 =TRUE&FALSE
set A12 =true=TRUE
set A13 =sum(1,2)
set A14 =Z999
set A15 =Z999+1
set Z999 5
set A16 =Z999*2
set A17 =AA1
set A18 =a1+b$2
set A19 =$B$2
set A20 =1E+
print A1:A20
show A5
dependents Z999
precedents A15
''')
hidden = CASES
examples = [
    case("ex-basic", "set A1 10\nset A2 20\nset A3 =SUM(A1:A2)*2\nget A3\nset A1 5\nget A3\nshow A3\nstats\n"),
    case("ex-cycle-error", "set A1 =B1+1\nset B1 =A1\nget A1\nset C1 =IFERROR(A1,0)+1\nget C1\nset B1 7\nget A1\nget C1\n"),
    case("ex-csv-copy", "import A1\nitem,qty,price,total\npen,3,1.5,=B2*C2\nink,2,4,=B3*C3\n.\ncopy D3 D4\nset D4 =SUM(D2:D3)\nexport\nexport formulas D2:D4\n"),
]
write_cases(examples, hidden)
