"""Generator for c60-issue-tracker. The expected outputs come from the Go oracle in oracle/*.ref (built with the local
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

WF = """workflow
  # simple board
  initial: todo
  todo -> doing, wontfix
  doing -> review requires assignee+points, todo
  review -> done requires labels, doing
  final: done, wontfix
end
"""

SEED = WF + """actor ann
today 2024-03-10
create "Fix login bug" priority=high points=5 labels=Bug,auth due=2024-03-01 assignee=bob
create "Add dark mode" points=3 labels=ui due=2024-04-01
create "Refactor database layer" priority=low points=13 labels=tech,db assignee=Carl
actor dave
create "Write docs" assignee=bob labels=docs due=2024-03-10
create "Crash on save" priority=critical points=2 labels=bug,ui assignee=carl due=2024-02-20
create "Upgrade deps" priority=medium labels=tech
move 1 doing
move 5 doing
actor eve
move 4 doing
comment 1 reproduced on staging
comment 3 needs design review
"""

def seeded(extra):
    return SEED + extra.strip("\n") + "\n"

CASES = []

def add(name, script):
    CASES.append(case(name, script.strip("\n") + "\n"))

def adds(name, extra):
    CASES.append(case(name, seeded(extra)))

# ---- workflow definitions
add("wf-basic", WF + "create a\nshow 1\n")
add("wf-no-workflow", "create x\nlist\nreport summary\nlist is:open\nview list\nlog\n")
add("wf-errors-initial-missing", "workflow\n a -> b\nend\ncreate x\n")
add("wf-errors-twice", "workflow\n initial: a\n initial: b\nend\nworkflow\n initial: a\n final: a\n a -> b\nend\nworkflow\n initial: A\nend\n")
add("wf-errors-guard", "workflow\n initial: a\n a -> b requires owner\nend\nworkflow\n initial: a\n a -> b requires assignee+due, c\n a -> b c\nend\nworkflow\n a b\n initial: x\nend\n")
add("wf-no-end-and-redefine", "workflow\n initial: a\n a -> b\n b -> a, c requires points\n final: c\nend\ncreate one\nworkflow\n initial: z\nend\ncreate two\nmove 1 b\nmove 1 c\nmove 1 a\n")
add("wf-replace-before-issues", "workflow\n initial: a\nend\nworkflow\n initial: b\n b -> c\n final: c\nend\ncreate x\nshow 1\nmove 1 a\nmove 1 c\nmove 1 c\n")
add("wf-final-with-transition", "workflow\n initial: a\n a -> b\n b -> a\n final: b\nend\nworkflow\n initial: a\n final: a\nend\ncreate x\n")

# ---- create/edit
adds("create-fields", """
create "Quoted \\"title\\" here" labels=B,a,A,b-c points=0 due=2024-02-29
create plain priority=medium
create x title=y
create "  " 
create ok points=007
create ok points=-1
create ok points=1000001
create ok due=2023-02-29
create ok due=2024-13-01
create ok priority=urgent
create ok labels=a!b
create ok assignee=
create ok state=done
create ok foo=1
create ok bar
create "unterminated
create
list id>6
log tail 8
""")
adds("edit-basic", """
edit 2 points=8 priority=high
edit 2 points=8
edit 2 title="Add dark mode v2" assignee=zed labels=ui,theme
edit 2 assignee=none points=none due=none labels=none
edit 2 reporter=none
show 2
edit 2
edit 2 title=
edit 2 state=doing
edit 99 title=x
edit abc title=x
edit #3 priority=critical priority=low
show #3
log 2
""")
adds("edit-final-and-bad", """
move 1 review
label 1 +auth
move 1 review
move 1 done
edit 1 title=zzz
label 1 +x
assign 1 someone
comment 1 still allowed
show 1
delete 1
list state:done
show 1
""")
adds("labels-cmd", """
label 1 +Urgent -bug +Urgent
label 1 -urgent -auth
label 1 -nothing
label 1 +a,b
label 1 +ok extra
label 6 +x +y -z
label 6 -x -y
label 6
label 99 +x
label 1 +
label 1 ""
assign 6
assign 6 frank
assign 6 FRANK
assign 6 frank
show 6
log 6
""")

# ---- move
adds("move-guards", """
move 2 review
move 2 doing
move 2 review
assign 2 gina
move 2 review
move 2 done
edit 2 labels=ui
move 2 done
move 2 todo
move 2 bogus
move 2 done
move 3 done
move 3 doing
move 3 doing
move 3 wontfix
move 3 todo
move 1
move
move x doing
""")
adds("move-comment", """
move 6 doing is this thing on? yes
move 6 todo   spaced   comment
comment 6   a  b  c
comment 6
comment
show 6
list text~spaced
list text~"is this"
log 6
""")
add("move-multi-guard", """
workflow
 initial: a
 a -> b requires assignee+points+due+labels+reporter
 b -> a
end
actor zed
create thing
move 1 b
edit 1 assignee=u points=1
move 1 b
edit 1 due=2025-01-01 labels=x reporter=none
move 1 b
edit 1 reporter=me
move 1 b
move 1 a
log
""")
adds("delete-and-ids", """
delete 2
delete 2
show 2
list
create fresh
show 7
log 2
log 7
log 8
log 0
log -1
report timeline 2
delete
delete x
""")

# ---- queries
adds("q-basics", """
list
list is:open
list is:final
list state:doing
list state:doing|review
list state!=todo
list state:bogus
list priority:high
list priority>=high
list priority<medium
list priority:high|critical
list priority>low|high
list priority>~high
list priority:urgent
list points>3
list points<=3
list points:none
list points!=none
list points:2|5
list points!=5
list points~3
list points>x
""")
adds("q-strings", """
list title~bug
list title~BUG
list title:"crash on save"
list title:Crash
list assignee:bob
list assignee:BOB
list assignee:none
list assignee!=bob
list assignee~ar
list assignee~none
list reporter:ann
list reporter:dave|eve
list text~staging
list text~"design review"
list text~login|design
list text:login
list title~"two words" extra
""")
adds("q-labels-dates", """
list label:bug
list label:BUG
list labels:ui
list label:none
list label!=bug
list label~ec
list label:bug|tech
list label:bug label:ui
list has:labels
list has:comments
list has:due
list has:points
list has:assignee
list has:reporter
list has:wrong
list due<2024-03-05
list due<=2024-03-10
list due>2024-03-10
list due>=2024-04-01
list due:2024-03-01
list due:none
list due!=none
list due:2024-03-01|2024-04-01
list due<none
list due<2024-02-31
list due~2024
list is:overdue
list is:unassigned
list is:overdue|unassigned
list is:bogus
list is>open
""")
adds("q-boolean", """
list label:bug AND label:ui
list label:bug OR label:tech
list label:bug OR label:tech AND priority:low
list (label:bug OR label:tech) AND priority:low
list NOT label:bug
list NOT NOT label:bug
list NOT (label:bug OR label:ui)
list label:bug label:ui
list is:open NOT assignee:none priority>=medium
list ((is:open) AND (NOT (priority:low)))
list priority:high OR
list AND priority:high
list (priority:high
list priority:high)
list ()
list NOT
list priority:high AND OR state:todo
list label:bug and label:ui
list foo
list title:"unterminated
list title~"(paren) quote"
""")
adds("q-ids-and-clock", """
list id:3
list id<3
list id>=5
list id:1|2|9
list id!=1
list id~1
list created:1
list created>=3 created<=5
list updated>8
list updated:0
list updated>x
list id<-1
list id:
list nofield:1
list :x
list Priority:high
""")
adds("q-sort-limit", """
list sort id
list sort -id
list sort priority
list sort -priority,id
list sort priority -points
list sort points
list sort -points
list sort due
list sort -due
list sort assignee,title
list sort -assignee
list sort title
list sort state,id
list sort -state
list sort reporter,-id
list sort created -updated
list sort updated
list sort bogus
list sort
list sort -
list limit 2
list sort -id limit 3
list limit 0
list limit 100
list limit x
list limit -1
list limit 2 limit 3
list is:open sort priority limit 2
list limit 2 sort id
list sort id,title limit 1
""")

# ---- views
adds("views-basic", """
view save urgent priority>=high is:open sort -priority,id
view save mine assignee:bob sort -id limit 5
view list
view show urgent
view show nope
view run urgent
view run mine
view run mine sort id
view run mine limit 1
view run mine sort title limit 1
view run mine extra
view run mine assignee:x
view run nope
view run
view save
view save Bad priority:low
view save 1x priority:low
view save ok
view save emptyview
view run emptyview limit 2
view save bad1 priority>>high
view save bad2 label:x sort nope
view save bad3 label:x limit zz
view save bad4 view:ghost
view save my-view_2 title~"a b"
view show my-view_2
view bogus
view show
view delete
view delete nope
view delete mine
view list
""")
adds("views-compose", """
view save open-bugs label:bug is:open
view save tech label:tech
view save both view:open-bugs OR view:tech sort id
view save notops NOT view:both limit 1
view run both
view run notops
view run notops limit 10
view list
view delete tech
view delete both
view save tech label:db
view run both
view save open-bugs view:both
view save a view:a
view save b view:both
view save open-bugs view:notops
view delete notops
view delete both
view delete open-bugs
view save open-bugs is:open
list view:open-bugs
list view:open-bugs sort -id
list view:nope
list view:a|b
list view>x
view list
""")
adds("views-live", """
view save todo state:todo sort id
view run todo
move 2 doing
view run todo
create brand new
view run todo
delete 6
view run todo
view save todo state:doing
view run todo
""")

# ---- bulk
adds("bulk-basic", """
bulk label +triaged where is:open
list label:triaged
bulk label -triaged where label:triaged
bulk assign pat where assignee:none
bulk assign pat where assignee:none
bulk set priority=low where priority:medium
bulk set points=1 due=2025-05-05 where id<=2
bulk move doing where state:todo
bulk move review where state:doing
bulk move done where state:review
list sort id
""")
adds("bulk-errors", """
bulk
bulk move
bulk move doing
bulk move doing where
bulk move where is:open
bulk move doing review where is:open
bulk assign where is:open
bulk assign a b where is:open
bulk label where is:open
bulk set where is:open
bulk set foo=1 where id:1
bulk set title= where id<=2
bulk set priority=bad where id:99
bulk delete where is:open
bulk move doing where priority>>x
bulk move doing where sort id
bulk move doing where limit 1
bulk label +ok where foo:bar
bulk set title="unterminated where id:1
bulk label +"a b" where id:1
bulk move wontfix where state:todo
bulk move doing where is:final
log tail 4
""")
adds("bulk-partial", """
bulk move review where is:open
bulk move doing where is:open
bulk move review where state:doing
bulk label +checked where id<=3
bulk set assignee=none where id<=3
bulk move wontfix where state:todo
bulk label +late where is:final
log tail 12
""")

# ---- log, reports
adds("log-views", """
log
log 1
log tail 3
log 1 tail 2
log 1 tail 0
log tail
log tail x
log 1 2
log 99
log tail 100
""")
adds("report-all", """
report summary
report workload
report labels
report labels is:open
report labels label:bug|ui
report labels priority:low AND priority:high
report labels sort id
report timeline 1
report timeline 3
report timeline 99
report timeline
report bogus
report
""")
adds("report-after-changes", """
move 2 doing
edit 2 assignee=BOB
assign 6 Bob
assign 3 carl
assign 5 CARL
edit 5 points=none
move 1 review
move 1 done
move 4 todo
report workload
report summary
report timeline 1
report timeline 4
today 2024-02-25
report summary
list is:overdue
today 2024-02-30
today
today 2025-01-01 extra
today 2000-02-29
today 1900-02-29
today 0000-01-01
""")
add("report-empty-workload", WF + "report workload\nreport summary\nreport labels\nlist\nview list\nlog\ncreate a\nmove 1 wontfix\nreport workload\nreport labels\nreport summary\n")
add("report-unassigned-last", WF + """
create a points=5
create b points=1 assignee=Zed
create c points=1 assignee=amy
create d points=1 assignee=AMY
create e points=9 assignee=bob
create f assignee=bob
create g assignee=cat points=1
report workload
""")
adds("actor-and-time", """
actor
actor a b
actor zed
create by zed
actor
comment 7 hello
move 7 doing hi
log 7
show 7
list reporter:zed
list reporter:ann
list created>=7 sort -created
""")
adds("unknown-commands", """
frobnicate
LIST
list  is:open   sort  -id
   show   1
	show 2
#comment line

show 3 extra
show
show 1 2
delete 1 2
""")
add("windows-newlines", WF.replace("\n", "\r\n") + "create a\r\nlist\r\nshow 1\r\n")
add("kitchen-sink", WF + """
actor ann
today 2024-06-01
create "Ship v1" priority=critical points=8 labels=release due=2024-06-15 assignee=zoe
create "Write changelog" priority=high points=2 labels=docs,release assignee=Zoe
create "Fix flaky test" priority=medium points=3 labels=bug,ci
create "Cleanup" priority=low labels=chore
view save release label:release sort -priority
view save stale is:open due<2024-06-01
move 1 doing
move 2 doing
move 2 review start
edit 2 labels=docs,release,ready
move 2 review
move 2 done shipped
bulk assign mia where assignee:none AND NOT label:chore
list view:release
view run release
bulk move doing where state:todo AND label:bug
report workload
report labels
report timeline 2
report summary
log tail 10
""")


adds("q-precedence", """
list priority:high OR priority:low AND label:db
list (priority:high OR priority:low) AND label:db
list NOT priority:high AND NOT priority:low
list NOT (priority:high AND is:open)
list is:open AND label:ui OR is:final
list state:todo label:tech OR label:bug label:ui
list label:bug label:ui OR label:docs
""")
adds("q-quoting", """
create "Spaced   title (with) parens" labels=x
create "AND OR NOT" labels=y
list title~"(with)"
list title~"AND OR"
list title:"AND OR NOT"
list title:"spaced   title (with) parens"
list text~"title (with"
list title~"a\\"b"
create "say \\"hi\\""
list title~"\\"hi\\""
show 8
show 7
""")
adds("edit-noop-and-clock", """
edit 1 priority=high
edit 1 labels=AUTH,bug
edit 1 labels=bug,auth,bug
edit 1 points=5 due=2024-03-01
edit 1 title="Fix login bug"
edit 1 reporter=ann
edit 1 reporter=dave
comment 1 x
list updated>=10
list created:1
log 1
""")
adds("sort-ties-missing", """
list sort -due,id
list sort due,-id
list sort -points,title
list sort points,-priority
list sort assignee,-id
list sort -reporter,-title
list sort priority,state,title
list sort -priority -state -id
""")
adds("sort-after-workflow-states", """
move 2 wontfix
move 3 doing
move 6 doing
move 6 todo
list sort state,id
list sort -state,id
list state!=todo sort -updated
""")
adds("bulk-views-and-labels", """
view save notdone NOT state:done
bulk label +seen -ui where view:notdone
list label:seen
bulk label -seen where label:ui
bulk set labels=none where view:notdone
list has:labels
bulk set labels=a,b where id:1
bulk label +c where id:1|2
bulk label +c where id:1|2
list label:c sort -id
""")
adds("report-labels-counts", """
label 1 +aa +zz
label 2 +zz
label 4 +zz
report labels
report labels state:todo
report labels NOT label:zz
report labels has:comments
""")
adds("timeline-detail", """
move 1 review
move 1 doing
comment 1 hm
move 1 review
move 1 done
create late
move 7 doing
report timeline 1
report timeline 7
report timeline 2
""")
adds("misc-errors", """
show 1.5
show 0
show +1
show #
show ##1
edit 1 =x
edit 1 title
edit 1 labels=a,,b
edit 1 labels=,
edit 1 points=1e3
edit 1 points=" 1"
comment 1 x
move 1 todo
move 1 doing
move 1 doing
""")
adds("view-sort-run-override", """
view save top priority>=medium sort -priority limit 2
view run top
view run top sort id
view run top limit 5
view run top sort -id limit 1
view run top sort bogus
view run top limit zz
view run top limit
view show top
""")

examples = [
    case("ex-workflow", WF + "actor ann\ncreate \"Fix it\" priority=high\nmove 1 doing\nassign 1 bob\nedit 1 points=3\nmove 1 review\nmove 1 doing sorry\nshow 1\nlog\n"),
    case("ex-query", seeded("""list is:open sort -priority,id limit 3
list (label:bug OR label:tech) AND NOT assignee:none
view save mine assignee:bob sort -id
view run mine
list priority>urgent
""")),
    case("ex-bulk-report", seeded("""bulk assign pat where assignee:none AND is:open
bulk move review where state:doing
report workload
report summary
report timeline 1
""")),
]
write_cases(examples, CASES)
