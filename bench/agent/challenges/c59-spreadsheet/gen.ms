# Generator for c59-spreadsheet. The expected outputs come from the Go oracle in oracle/*.ref (built with the
# local Go toolchain); this file only supplies the inputs. Deterministic; run: ms run bench/agent/gen.ms -- c59
import Cases, build_oracle, write_cases from "../../lib/gen.ms"

fn add(var cs: Cases, name: String, script: String) Unit:
    cs.push(name, strip_nl(script))

fn strip_nl(text: String) String:
    var chars = text.chars()
    var start = 0
    var end = chars.length()
    while start < end and chars[start] == "\n":
        start += 1
    while end > start and chars[end - 1] == "\n":
        end -= 1
    return chars.slice(start, end).get([]).join("") + "\n"

# `set KEY VALUE` lines for the flat list `pairs` of keys and values.
fn sets(pairs: List[String]) String:
    var out = ""
    var k = 0

    while k < pairs.length():
        out += "set " + pairs[k] + " " + pairs[k + 1] + "\n"
        k += 2

    return out

export fn gen_c59() Unit:
    var cs = Cases(build_oracle("c59-spreadsheet"))
    add(
        var cs, "value-types",
        "\nset A1 42\nset A2 -3.5\nset A3 1e3\nset A4 .5\nset A5 +7\nset A6 TRUE\nset A7 false\nset A8 hello world\nset A9 '123\nset A10 '=not a formula\nset A11   spaced   out  \nset A12 1,5\nset A13 0x10\nset A14 12abc\nset A15 -0\nset A16 1e400\nset A17 007\nget A1\nget A2\nget A3\nget A4\nget A5\nget A6\nget A7\nget A8\nget A9\nget A10\nget A11\nget A12\nget A13\nget A14\nget A15\nget A16\nget A17\nget B1\nshow A9\nshow A10\nshow A11\nshow A6\nshow B1\nprint\n"
    )

    var gets = ""
    for i in 1..15:
        gets += "get A{i}\n"
    add(
        var cs,
        "number-formatting",
        sets(
            [
                "A1", "=1/3", "A2", "=2/3", "A3", "=0.1+0.2", "A4", "=1e15", "A5",
                "=123456789.123456789", "A6", "=1e-11", "A7", "=-1/3", "A8",
                "=1000000*1000000", "A9", "=5e-10", "A10", "=0.00000000005", "A11",
                "=100/3", "A12", "=2^0.5", "A13", "=-0", "A14", "=0*-1"
            ]
        ) + gets + "print A1:A14\n"
    )
    add(
        var cs, "clear-and-overwrite",
        "\nset A1 5\nset A2 =A1*2\nget A2\nclear A1\nget A1\nget A2\nset A1 text\nget A2\nset A2 99\nshow A2\nclear A2\nget A2\nclear A2\nshow A2\nset A3\nget A3\nset A4    \nstats\n"
    )
    add(
        var cs, "operator-precedence",
        "\nset A1 =1+2*3\nset A2 =(1+2)*3\nset A3 =-2^2\nset A4 =2^3^2\nset A5 =2^-1\nset A6 =-(2+3)*2\nset A7 =10-4-3\nset A8 =100/10/5\nset A9 =2*3^2\nset A10 =--5\nset A11 =+-+3\nset A12 =\"a\"&1+2&\"b\"\nset A13 =1+1=2\nset A14 =1<2=TRUE\nset A15 =3>2<>FALSE\nset A16 =2^2*3\nset A17 =1&2=12\nset A18 =-2^-2\nset A19 =7-+2\nset A20 =(((1)))\nprint A1:A20\n"
    )
    add(
        var cs, "coercions",
        "\nset A1 5\nset B1 \"5\"\nset A2 =A1+\"3\"\nset A3 =\"3\"*\"4\"\nset A4 =TRUE+TRUE\nset A5 =C1+5\nset A6 =C1&\"x\"\nset A7 =\"abc\"+1\nset A8 =\"\"+1\nset A9 =\" 12 \"+1\nset A10 =\"1e2\"+0\nset A11 =FALSE*5\nset A12 =-\"5\"\nset A13 =-\"x\"\nset A14 =C1*C2\nset A15 =A5&A6&TRUE&1.50\nprint A1:A15\n"
    )
    add(
        var cs, "comparisons",
        "\nset A1 5\nset A2 apple\nset A3 Apple\nset A4 TRUE\nset B1 =A1=5\nset B2 =A1<>5\nset B3 =A2=\"apple\"\nset B4 =A2=A3\nset B5 =A2<A3\nset B6 =A1<A2\nset B7 =A2<A4\nset B8 =A1<A4\nset B9 =C1=0\nset B10 =C1=\"\"\nset B11 =C1=C2\nset B12 =C1<1\nset B13 =A4=TRUE\nset B14 =A4>FALSE\nset B15 =\"a\"<\"b\"\nset B16 =\"B\"<\"a\"\nset B17 =\"10\"<\"9\"\nset B18 =10<9\nset B19 =C1=FALSE\nset B20 =A1>=5\nset B21 =A1<=4\nprint B1:B21\n"
    )
    add(
        var cs, "errors-basic",
        "\nset A1 =1/0\nset A2 =A1+1\nset A3 =nosuch(1)\nset A4 =B9+nosuch\nset A5 =A1\nset A6 =A3&A1\nset A7 =A1+A3\nset A8 =A3+A1\nset A9 =IFERROR(A1,\"ok\")\nset A10 =ISERROR(A2)\nset A11 =ISERROR(5)\nset A12 =IF(A1,1,2)\nset A13 =SUM(A1,A3)\nset A14 =SUM(A3,A1)\nset A15 =AAA1\nset A16 =A1000\nset A17 =#REF!\nset A18 =SUM(#REF!,1)\nset A19 =A1:A2\nset A20 =1+A1:A2\nset A21 =SQRT(-1)\nset A22 =0^-1\nset A23 =10^400\nset A24 =MOD(1,0)\nset A25 =ABS(A1:A2)\nprint A1:A25\n"
    )
    add(
        var cs, "errors-parse",
        "\nset A1 =\nset A2 =1+\nset A3 =(1\nset A4 =1)\nset A5 =1 2\nset A6 =@\nset A7 =\"abc\nset A8 =SUM(1,)\nset A9 =SUM(,1)\nset A10 =1..2\nset A11 =A1 A2\nset A12 =*3\nset A13 =SUM(1\nset A14 =$\nset A15 =1+#X\nset A16 =A1 B1\nset A17 = 1 + 2 \nset A18 =sum( 1 , 2 )\nset A19 =SUM()\nset A20 =IF()\nprint A1:A20\nshow A2\nget A2\nset A2 =1+1\nget A2\nstats\n"
    )
    add(
        var cs, "sum-avg-min-max",
        "\nset A1 1\nset A2 text\nset A3 TRUE\nset A4 4\nset A6 6\nset B1 =SUM(A1:A6)\nset B2 =AVERAGE(A1:A6)\nset B3 =MIN(A1:A6)\nset B4 =MAX(A1:A6)\nset B5 =COUNT(A1:A6)\nset B6 =COUNTA(A1:A6)\nset B7 =SUM(A1,A4,10)\nset B8 =SUM(A1:A6,100)\nset B9 =SUM(\"5\",TRUE,A1)\nset B10 =SUM(\"x\")\nset B11 =AVERAGE(C1:C5)\nset B12 =MIN(C1:C5)\nset B13 =MAX(C1:C5,-3)\nset B14 =PRODUCT(A1,A4,A6)\nset B15 =PRODUCT(C1:C3)\nset B16 =MEDIAN(A1,A4,A6)\nset B17 =MEDIAN(1,2,3,4)\nset B18 =MEDIAN(C1:C2)\nset B19 =SUM(A1:A6,B1)\nset B20 =COUNT(A1,\"3\",TRUE,A2)\nset B21 =COUNTA(C1:C3)\nset B22 =SUM(B1:B20)\nset B23 =AVERAGE(A1,A4)\nset B24 =SUM(A6:A1)\nset B25 =SUM(A1:A1)\nprint B1:B25\n"
    )
    add(
        var cs, "aggregate-errors-in-range",
        "\nset A1 1\nset A2 =1/0\nset A3 =nosuch()\nset A4 3\nset B1 =SUM(A1:A4)\nset B2 =SUM(A3:A4)\nset B3 =COUNT(A1:A4)\nset B4 =COUNTA(A1:A4)\nset B5 =MAX(A1:A4)\nset B6 =AVERAGE(A4:A1)\nset B7 =IFERROR(SUM(A1:A4),-1)\nset B8 =CONCAT(A1:A4)\nset B9 =AND(A1:A4)\nset B10 =COUNTIF(A1:A4,\">0\")\nprint B1:B10\n"
    )
    add(
        var cs, "logic-functions",
        "\nset A1 =IF(TRUE,\"y\",\"n\")\nset A2 =IF(0,\"y\",\"n\")\nset A3 =IF(2,\"y\")\nset A4 =IF(FALSE,\"y\")\nset A5 =IF(\"true\",1,2)\nset A6 =IF(\"maybe\",1,2)\nset A7 =IF(C1,1,2)\nset A8 =IF(TRUE,1,1/0)\nset A9 =IF(FALSE,1/0,2)\nset A10 =IF(TRUE,A1:A2,0)\nset A11 =AND(TRUE,1,\"true\")\nset A12 =AND(TRUE,FALSE,1/0)\nset A13 =OR(FALSE,0,\"false\")\nset A14 =OR(1/0,TRUE)\nset A15 =AND()\nset A16 =NOT(0)\nset A17 =NOT(\"x\")\nset A18 =NOT(C1)\nset A19 =AND(C1:C3)\nset A20 =OR(B1:B2,TRUE)\nset B1 text\nset B2 5\nset A21 =OR(B1:B2)\nset A22 =AND(B1:B2)\nset A23 =CHOOSE(2,\"a\",\"b\",\"c\")\nset A24 =CHOOSE(4,\"a\",\"b\",\"c\")\nset A25 =CHOOSE(1,1/0,2)\nset A26 =CHOOSE(0,1)\nset A27 =CHOOSE(2.9,10,20,30)\nset A28 =IFERROR(1/0,IFERROR(nosuch(),\"deep\"))\nset A29 =IFERROR(5,1/0)\nprint A1:A28\nget A29\n"
    )
    add(
        var cs, "text-functions",
        "\nset A1 Hello World\nset A2 =LEN(A1)\nset A3 =UPPER(A1)\nset A4 =LOWER(A1)\nset A5 =LEFT(A1)\nset A6 =LEFT(A1,5)\nset A7 =RIGHT(A1,5)\nset A8 =RIGHT(A1)\nset A9 =MID(A1,7,3)\nset A10 =MID(A1,7,100)\nset A11 =MID(A1,50,3)\nset A12 =LEFT(A1,100)\nset A13 =LEFT(A1,0)\nset A14 =LEFT(A1,-1)\nset A15 =MID(A1,0,1)\nset A16 =TRIM(\"  a   b  c  \")\nset A17 =CONCAT(\"a\",1,TRUE,C1,\"b\")\nset A18 =CONCAT(A2:A4)\nset A19 =SUBSTITUTE(A1,\"o\",\"0\")\nset A20 =SUBSTITUTE(A1,\"\",\"x\")\nset A21 =SUBSTITUTE(A1,\"World\",\"\")\nset A22 =LEN(12345)\nset A23 =LEN(C1)\nset A24 =VALUE(\"3.5\")\nset A25 =VALUE(\"abc\")\nset A26 =VALUE(TRUE)\nset A27 =VALUE(\" 7 \")\nset A28 =LEFT(1234,2)+1\nset A29 =UPPER(A1:A2)\nset A30 =LEN()\nprint A1:A30\n"
    )
    add(
        var cs, "math-functions",
        "\nset A1 =ROUND(2.5)\nset A2 =ROUND(-2.5)\nset A3 =ROUND(1.2345,2)\nset A4 =ROUND(1234.5678,-2)\nset A5 =ROUND(0.5,0)\nset A6 =ROUND(1.005,2)\nset A7 =ROUND(2.675,2)\nset A8 =ROUND(5,20)\nset A9 =INT(-1.5)\nset A10 =INT(1.9)\nset A11 =ABS(-4.25)\nset A12 =SQRT(16)\nset A13 =SQRT(2)\nset A14 =POW(2,10)\nset A15 =POW(-8,1/3)\nset A16 =MOD(10,3)\nset A17 =MOD(-10,3)\nset A18 =MOD(10,-3)\nset A19 =MOD(5.5,2)\nset A20 =MOD(-1,5)\nset A21 =ABS(\"x\")\nset A22 =ROUND(1.5,1.9)\nset A23 =INT(-0.5)\nset A24 =POW(0,0)\nset A25 =POW(2,0.5)\nprint A1:A25\n"
    )
    add(
        var cs, "info-functions",
        "\nset A1 5\nset A2 text\nset B1 =ISBLANK(A1)\nset B2 =ISBLANK(C5)\nset B3 =ISNUMBER(A1)\nset B4 =ISNUMBER(A2)\nset B5 =ISTEXT(A2)\nset B6 =ISTEXT(A1)\nset B7 =ISNUMBER(\"5\")\nset B8 =ISBLANK(\"\")\nset B9 =ROW(C7)\nset B10 =COLUMN(C7)\nset B11 =ROW(B3:D9)\nset B12 =COLUMN(B3:D9)\nset B13 =ROW(5)\nset B14 =ROW(AA1)\nset B15 =ISNUMBER(1/0)\nset B16 =ISERROR(nosuch())\nset B17 =ROW(B17)\nprint B1:B17\ndependents B17\nprecedents B17\n"
    )
    add(
        var cs, "index-function",
        "\nset A1 1\nset B1 2\nset C1 3\nset A2 4\nset B2 5\nset C2 6\nset E1 =INDEX(A1:C2,2,3)\nset E2 =INDEX(A1:C2,1,1)\nset E3 =INDEX(A1:C2,3,1)\nset E4 =INDEX(A1:C2,1,4)\nset E5 =INDEX(A1:C1,2)\nset E6 =INDEX(A1:A2,2)\nset E7 =INDEX(A1:C2,0,1)\nset E8 =INDEX(A1,1)\nset E9 =INDEX(A2:C2,3)\nset E10 =INDEX(A1:C2,2.9,1.9)\nprint E1:E10\n"
    )
    add(
        var cs, "countif",
        "\nset A1 5\nset A2 10\nset A3 apple\nset A4 Apple\nset A5 TRUE\nset A6 15\nset A7 banana\nset B1 =COUNTIF(A1:A7,10)\nset B2 =COUNTIF(A1:A7,\">5\")\nset B3 =COUNTIF(A1:A7,\">=10\")\nset B4 =COUNTIF(A1:A7,\"<10\")\nset B5 =COUNTIF(A1:A7,\"<>10\")\nset B6 =COUNTIF(A1:A7,\"apple\")\nset B7 =COUNTIF(A1:A7,\"=apple\")\nset B8 =COUNTIF(A1:A7,\"<>apple\")\nset B9 =COUNTIF(A1:A8,\"b\")\nset B10 =COUNTIF(A1:A7,TRUE)\nset B11 =COUNTIF(A1:A7,\">a\")\nset B12 =COUNTIF(A1:A7,\"\")\nset B13 =COUNTIF(A1:A7,\"5\")\nset B14 =COUNTIF(A1:A7,A6)\nset B15 =COUNTIF(A1,5)\nset B16 =COUNTIF(5,5)\nprint B1:B16\n"
    )
    add(
        var cs, "dependency-chain-recalc",
        "\nset A1 1\nset A2 =A1+1\nset A3 =A2+1\nset A4 =A3+1\nset A5 =A4+1\nstats\nset A1 10\nset A1 10\nset A3 100\nset A5 =A1\nstats\nclear A2\nget A4\nstats\nshow A4\ndependents A1\ndependents A2\nprecedents A4\n"
    )
    add(
        var cs, "dependency-diamond-and-ranges",
        "\nset A1 1\nset B1 =A1*2\nset B2 =A1*3\nset C1 =B1+B2\nset C2 =SUM(A1:B2)\nset C3 =SUM(B1:B2)+C1\nset D1 =C3\nstats\nset A1 2\nstats\nset B2 5\nstats\nset Z9 7\nstats\nset A2 9\nstats\nprint A1:D3\ndependents A1\ndependents B2\nprecedents C2\nprecedents C3\nprecedents D1\n"
    )
    add(
        var cs, "recalc-counts-unchanged-value",
        "\nset A1 5\nset A2 =A1*0\nset A3 =A2+1\nset A4 =A3\nset A1 6\nset A1 6\nset A1 text\nset A1 =1\nstats\n"
    )
    add(
        var cs, "range-dependency-empty-cells",
        "\nset B1 =SUM(A1:A3)\nget B1\nset A2 4\nget B1\nset A3 =A2*2\nget B1\nclear A2\nget B1\ndependents A2\ndependents A3\nprecedents B1\nset B2 =SUM(A3:A1)\nprecedents B2\nset B3 =COUNT(C1:E3)\nprecedents B3\nstats\n"
    )
    add(
        var cs, "cycles-basic",
        "\nset A1 =A1\nget A1\nset B1 =B2\nset B2 =B1\nget B1\nget B2\nset C1 =B1+1\nget C1\nset D1 =IFERROR(B1,\"safe\")\nget D1\nset B2 5\nget B1\nget C1\nget D1\nset A1 =1\nget A1\nstats\n"
    )
    add(
        var cs, "cycles-three-and-range",
        "\nset A1 =A2+1\nset A2 =A3+1\nset A3 =A1+1\nget A1\nget A2\nget A3\nset B1 =SUM(A1:A3)\nget B1\nset C1 =SUM(C1:C3)\nget C1\nset D1 =D2\nset D2 =D3\nset D3 =5\nget D1\nset D3 =D1\nget D1\nget D3\nset D3 0\nget D1\nset E1 =IF(TRUE,1,E1)\nget E1\nset E2 =ROW(E2)\nget E2\nset A2 7\nget A1\nget A3\nget B1\nprint A1:E3\n"
    )
    add(
        var cs, "cycles-break-and-reform",
        "\nset A1 =B1\nset B1 =C1\nset C1 =A1\nset D1 =A1&\"?\"\nset E1 =IFERROR(D1,\"err\")\nshow D1\nget E1\nset C1 1\nget A1\nget B1\nget C1\nget D1\nget E1\nset C1 =A1\nget E1\nset C1 =D1\nget E1\ndependents A1\nstats\n"
    )
    add(
        var cs, "cycle-with-outside-formula",
        "\nset A1 =B1+C1\nset B1 =A1+1\nset C1 =10\nset D1 =A1+B1+C1\nset E1 =IFERROR(A1,0)+1\nget A1\nget B1\nget D1\nget E1\nset B1 5\nget A1\nget B1\nget D1\nget E1\n"
    )
    add(
        var cs, "copy-relative-absolute",
        "\nset A1 1\nset A2 2\nset A3 3\nset B1 =A1*2\nset B2 =$A1+A$1\nset B3 =$A$1+A1\nset C1 =SUM(A1:A3)\nset C2 =SUM($A1:A$3)\nset C3 =SUM($A$1:$A$3)\ncopy B1 D1\ncopy B2 D2:D3\ncopy B3 E3\ncopy C1 F1:G2\ncopy C2 H5\ncopy C3 I5:J6\nshow D1\nshow D2\nshow D3\nshow E3\nshow F1\nshow G2\nshow H5\nshow I5\nshow J6\nprint D1:J6\n"
    )
    add(
        var cs, "copy-out-of-range-and-strings",
        "\nset B2 =A1+\"A1\"&A1\nset C3 =SUM(A1:B2)&\" A1\"\nset D4 =Z999+A1\ncopy B2 A1\nshow A1\nget A1\ncopy C3 A1:B2\nshow A1\nshow B1\nshow A2\nshow B2\ncopy D4 E5\nshow E5\nget E5\ncopy D4 C3\nshow C3\ncopy D4 A1\nshow A1\n"
    )
    add(
        var cs, "copy-constants-and-empty",
        "\nset A1 hello\nset A2 5\nset A3 =A2\ncopy A1 B1:B3\ncopy A2 C1:C2\ncopy Z9 A1\nget A1\ncopy A3 B3\ncopy A3 A3\nshow A3\nget B3\nprint A1:C3\ndependents A2\n"
    )
    add(
        var cs, "copy-chain-incremental",
        "\nset A1 1\nset A2 =A1+1\ncopy A2 A3:A200\nget A200\nstats\nset A1 100\nget A200\nstats\nset A100 =0\nget A200\nstats\ndependents A198\nprecedents A200\n"
    )
    add(
        var cs, "csv-import-export",
        "\nimport A1\nname,qty,price,total\napple,3,1.5,=B2*C2\n\"pear, ripe\",2,2.25,=B3*C3\nbanana,12,0.25,=B4*C4\ntotal,=SUM(B2:B4),,=SUM(D2:D4)\n.\nprint\nexport\nexport formulas\nexport A1:B2\nexport formulas C2:D3\nget D5\nset B2 10\nexport D1:D5\n"
    )
    add(
        var cs, "csv-quoting-roundtrip",
        "\nset A1 plain\nset A2 \"He said \"\"hi\"\"\"\nset A3 a,b\nset A4 ' leading space\nset A5 trailing space \nset A6 =CONCAT(\"x\",\",\",\"y\")\nset A7 line1\nset A8 =\"\"\nset A9 =\"q\"\"q\"\nexport\nexport formulas\nimport C1\n\"multi\nline\",\"quoted \"\"x\"\"\",,end\na,b\n.\nget C1\nget D1\nget E1\nget F1\nprint C1:F2\n"
    )
    add(
        var cs, "csv-import-types",
        "\nimport B2\n1,2.5,abc,TRUE,false\n'007,=A1,=B2+C2, spaced ,\"quoted number\"\n,,,,\n\"=1+1\",x\n.\nprint A1:F5\nstats\nset B3 =SUM(B2:D2)\nimport B3\n7,8\n.\nget B3\ndependents B3\n"
    )
    add(
        var cs, "csv-import-overwrite-and-clear",
        "\nset A1 1\nset A2 2\nset A3 =A1+A2\nset A4 =A3*2\nimport A1\n,10\n\n5\n.\nprint A1:C4\nstats\nget A4\n"
    )
    add(
        var cs, "csv-import-range-errors",
        "\nimport Z999\n1,2\n.\nget Z999\nimport Z1\n1,2\n.\nimport A999\n1\n2\n.\nget A999\nimport A1\n.\nimport\nimport A0\nx\n.\nimport AA1\nx\n.\nstats\n"
    )
    add(
        var cs, "print-and-export-ranges",
        "\nset A1 1\nset B2 hello\nset C3 =A1+1\nprint\nprint B2:C3\nprint C3:B2\nprint A1\nprint Z1:Z2\nexport B2:B2\nprint A1:\nprint 1A\nprint A1 B2\nexport formulas A1:C3\nprint formulas\nexport values B2:C3\nexport\n"
    )
    add(
        var cs, "command-errors",
        "\nfrobnicate\nset\nset A1\nset AA1 5\nset A0 5\nset A1000 5\nset a1 7\nget a1\nget\nget A1 B1\nget 11\nshow\nclear\nclear A1 A2\nprecedents\ndependents A1 A2\nstats extra\ncopy A1\ncopy A1 B1 C1\ncopy A1 ZZ\ncopy 1 A1\nprecedents Q\n"
    )
    add(
        var cs, "case-insensitive",
        "\nset a1 5\nset b2 =sum(A1:a1)+Sum(a1)\nset c3 =If(true,\"Y\",\"N\")\nset d4 =b2&c3\nprint A1:D4\nshow B2\nget b2\ncopy b2 e5\nshow E5\n"
    )
    add(
        var cs, "whitespace-and-formula-text",
        "\nset A1    =  1 +   2  \nshow A1\nset A2 =SUM( A1 ,  2 )\nshow A2\nset A3 = 5\nget A3\nshow A3\nset A4 =\"  keep  \"\nget A4\nset A5 text with   inner   spaces\nshow A5\n"
    )
    add(
        var cs, "budget-scenario",
        "\nimport A1\nitem,jan,feb,mar,total\nrent,1200,1200,1200,=SUM(B2:D2)\nfood,300,320.5,298.75,=SUM(B3:D3)\nfun,100,80,150,=SUM(B4:D4)\ntotal,=SUM(B2:B4),=SUM(C2:C4),=SUM(D2:D4),=SUM(E2:E4)\navg,=AVERAGE(B2:B4),=AVERAGE(C2:C4),=AVERAGE(D2:D4),=AVERAGE(E2:E4)\nmax,=MAX(B2:B4),=MAX(C2:C4),=MAX(D2:D4),=MAX(E2:E4)\n.\nprint\nstats\nset C3 400\nget E5\nget F5\nset F1 over\nset F2 =IF(E2>3500,\"over\",\"ok\")\ncopy F2 F3:F4\nprint E1:F4\nset B2 =B2\nget B2\nget E2\nstats\n"
    )
    add(
        var cs, "grade-book",
        "\nimport A1\nstudent,hw1,hw2,exam,avg,grade\nann,90,80,70,,\nbob,60,,95,,\ncy,100,100,100,,\n.\nset E2 =AVERAGE(B2:D2)\ncopy E2 E3:E4\nset F2 =IF(E2>=90,\"A\",IF(E2>=80,\"B\",IF(E2>=70,\"C\",\"F\")))\ncopy F2 F3:F4\nprint\nset C3 75\nprint E1:F4\nset G1 =COUNTIF(F2:F4,\"A\")\nget G1\nset G2 =COUNTIF(E2:E4,\">=80\")\nget G2\nstats\n"
    )
    add(
        var cs, "loan-table",
        "\nset A1 principal\nset B1 10000\nset A2 rate\nset B2 0.05\nset A3 months\nset B3 12\nset A4 payment\nset B4 =ROUND(B1*(B2/12)/(1-POW(1+B2/12,-B3)),2)\nset A6 month\nset B6 balance\nset C6 interest\nset D6 principal\nset B7 =B1\nset C7 =ROUND(B7*$B$2/12,2)\nset D7 =$B$4-C7\nset A7 1\nset A8 =A7+1\nset B8 =ROUND(B7-D7,2)\ncopy B8 B9:B18\ncopy C7 C8:C18\ncopy D7 D8:D18\ncopy A8 A9:A18\nget B4\nprint A6:D18\nget B18\nset B1 20000\nget B4\nget B18\nstats\n"
    )
    add(
        var cs, "gradual-big-grid",
        "\nset A1 1\nset B1 =A1+1\ncopy B1 C1:Z1\ncopy A1 A2:A60\nset A2 =A1+1\ncopy A2 A3:A60\ncopy B1 B2:Z60\nget Z60\nget A60\nstats\nset A1 2\nget Z60\nstats\nset N30 =0\nget Z60\nstats\n"
    )
    add(
        var cs, "sum-of-totals-dependents",
        "\nset A1 =B1+C1\nset A2 =B2+C2\nset A3 =SUM(A1:A2)\nset B1 1\nset C1 2\nset B2 3\nset C2 4\nget A3\ndependents B1\ndependents C2\ndependents A1\nset B1 =A3\nget A1\nget A3\ndependents B1\n"
    )
    add(
        var cs, "formula-literals",
        "\nset A1 =1.5E3\nset A2 =.5+.5\nset A3 =1.+1\nset A4 =1e2+1E-2\nset A5 =\"say \"\"hi\"\"\"\nset A6 =\"\"\"\"\nset A7 =LEN(A6)\nset A8 =\" a \"&\"b\"\nset A9 =1E\nset A10 =2e+3\nset A11 =TRUE&FALSE\nset A12 =true=TRUE\nset A13 =sum(1,2)\nset A14 =Z999\nset A15 =Z999+1\nset Z999 5\nset A16 =Z999*2\nset A17 =AA1\nset A18 =a1+b$2\nset A19 =$B$2\nset A20 =1E+\nprint A1:A20\nshow A5\ndependents Z999\nprecedents A15\n"
    )

    let examples = [
        cs.make(
            "ex-basic",
            "set A1 10\nset A2 20\nset A3 =SUM(A1:A2)*2\nget A3\nset A1 5\nget A3\nshow A3\nstats\n"
        ),
        cs.make(
            "ex-cycle-error",
            "set A1 =B1+1\nset B1 =A1\nget A1\nset C1 =IFERROR(A1,0)+1\nget C1\nset B1 7\nget A1\nget C1\n"
        ),
        cs.make(
            "ex-csv-copy",
            "import A1\nitem,qty,price,total\npen,3,1.5,=B2*C2\nink,2,4,=B3*C3\n.\ncopy D3 D4\nset D4 =SUM(D2:D3)\nexport\nexport formulas D2:D4\n"
        )
    ]
    write_cases("c59-spreadsheet", examples, cs.list)
