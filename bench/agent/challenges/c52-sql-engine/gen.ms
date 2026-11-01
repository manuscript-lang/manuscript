# Generator for c52-sql-engine. The expected outputs come from the Go oracle in oracle/*.ref (built with the
# local Go toolchain); this file only supplies the inputs. Deterministic; run: ms run bench/agent/gen.ms -- c52
import Cases, build_oracle, write_cases from "../../lib/gen.ms"

let SETUP = "CREATE TABLE dept (id INT PRIMARY KEY, name TEXT NOT NULL, city TEXT);\nCREATE TABLE emp (id INT PRIMARY KEY, name TEXT NOT NULL, dept_id INT, salary INT, title TEXT);\nINSERT INTO dept VALUES (1, 'Engineering', 'Berlin'), (2, 'Sales', 'Paris'), (3, 'Support', NULL), (4, 'Legal', 'Rome');\nINSERT INTO emp VALUES\n  (1, 'Alice', 1, 120, 'lead'),\n  (2, 'Bob', 1, 100, 'dev'),\n  (3, 'Carol', 2, 90, 'rep'),\n  (4, 'Dan', 2, 95, 'rep'),\n  (5, 'Eve', NULL, 70, NULL),\n  (6, 'Frank', 3, 60, 'agent'),\n  (7, 'Grace', 1, 100, 'dev'),\n  (8, 'Heidi', 3, NULL, 'agent');\n"

fn add(var cs: Cases, name: String, script: String, setup: Bool = true) Unit:
    cs.push(name, (if setup: SETUP else: "") + script)

# Larger generated data sets (deterministic arithmetic, no randomness).
fn gen_big() String:
    var lines = [
        "CREATE TABLE sales (id INT PRIMARY KEY, region TEXT, item TEXT, qty INT, price INT, note TEXT);"
    ]
    let regions = ["north", "south", "east", "west"]
    let items = ["bolt", "nut", "gear", "cog", "pin", "cam"]
    var vals = List[String]()
    var x = 7

    for i in 1..121:
        x = (x * 31 + 17) % 1009

        let r = regions[x % 4]
        let it = items[x / 4 % 6]
        let qty = x % 13 + 1
        let price = x / 7 % 50 + 5
        let note = if x % 9 == 0: "NULL" else: "'n{x % 5}'"
        vals.append("({i}, '{r}', '{it}', {qty}, {price}, {note})")

    var i = 0

    while i < vals.length():
        lines.append(
            "INSERT INTO sales VALUES " + vals.slice(
                i, if i + 20 < vals.length(): i + 20 else: vals.length()
            ).get([]).join(", ") + ";"
        )
        i += 20

    return lines.join("\n") + "\n"

export fn gen_c52() Unit:
    var cs = Cases(build_oracle("c52-sql-engine"))
    let big = gen_big()
    add(
        var cs, "basic-ddl-dml",
        "SELECT * FROM dept;\nSELECT name, salary FROM emp WHERE salary > 95 ORDER BY name;\nUPDATE emp SET salary = salary + 5 WHERE dept_id = 2;\nSELECT name, salary FROM emp WHERE dept_id = 2;\nDELETE FROM emp WHERE salary IS NULL;\nSELECT COUNT(*) FROM emp;\n"
    )
    add(var cs, "select-star-order", "SELECT * FROM emp ORDER BY salary DESC, name;\n")
    add(
        var cs, "select-no-from",
        "SELECT 1 + 2 * 3, 'a' || 'b', 10 / 3, -7 % 3, 7 % -3, -(2 + 3);\nSELECT 1 < 2, 1 = 2, NULL, NULL = NULL, NULL IS NULL, 5 IS NOT NULL;\nSELECT 1 WHERE 1 = 2;\nSELECT COUNT(*), SUM(3), MAX('x');\n",
        setup: false
    )
    add(
        var cs, "where-logic",
        "SELECT name FROM emp WHERE dept_id = 1 AND salary >= 100 OR title = 'rep' ORDER BY id;\nSELECT name FROM emp WHERE NOT (dept_id = 1 OR dept_id = 2) ORDER BY id;\nSELECT name FROM emp WHERE dept_id <> 1 ORDER BY id;\nSELECT name FROM emp WHERE dept_id != 1 ORDER BY id;\nSELECT name FROM emp WHERE salary < 100 AND salary > 60 ORDER BY id;\n"
    )
    add(
        var cs, "null-semantics",
        "SELECT name FROM emp WHERE dept_id = NULL;\nSELECT name FROM emp WHERE dept_id IS NULL;\nSELECT name FROM emp WHERE title IS NOT NULL AND dept_id IS NOT NULL ORDER BY id;\nSELECT name, salary + 1, title || '!' FROM emp WHERE id >= 5 ORDER BY id;\nSELECT id FROM emp WHERE NOT (salary > 90) ORDER BY id;\nSELECT NULL AND 1 = 2, NULL OR 1 = 1, NULL AND 1 = 1, NOT NULL;\n"
    )
    add(
        var cs, "like-in-between",
        "SELECT name FROM emp WHERE name LIKE 'A%' OR name LIKE '%e' ORDER BY id;\nSELECT name FROM emp WHERE name LIKE '_ob' OR name LIKE '__ce';\nSELECT name FROM emp WHERE name NOT LIKE '%a%' ORDER BY id;\nSELECT name FROM emp WHERE id IN (1, 3, 5, 99) ORDER BY id;\nSELECT name FROM emp WHERE id NOT IN (1, 2, 3, 4) ORDER BY id;\nSELECT name FROM emp WHERE salary BETWEEN 90 AND 100 ORDER BY id;\nSELECT name FROM emp WHERE salary NOT BETWEEN 90 AND 100 ORDER BY id;\nSELECT 3 IN (1, NULL), 3 IN (3, NULL), 3 NOT IN (1, NULL), NULL IN (1), 'x' LIKE NULL;\n"
    )
    add(
        var cs, "order-limit-offset",
        "SELECT name FROM emp ORDER BY salary, name;\nSELECT name FROM emp ORDER BY salary DESC, name ASC LIMIT 3;\nSELECT name FROM emp ORDER BY id LIMIT 3 OFFSET 2;\nSELECT name FROM emp ORDER BY id LIMIT 0;\nSELECT name FROM emp ORDER BY id LIMIT 5 OFFSET 100;\nSELECT name, salary AS pay FROM emp ORDER BY pay DESC, 1 LIMIT 4;\nSELECT name, salary FROM emp ORDER BY 2, 1;\nSELECT name FROM emp ORDER BY LENGTH(name) DESC, name;\nSELECT title, name FROM emp ORDER BY title, name;\n"
    )
    add(
        var cs, "distinct",
        "SELECT DISTINCT dept_id FROM emp ORDER BY dept_id;\nSELECT DISTINCT title FROM emp ORDER BY title DESC;\nSELECT DISTINCT dept_id, title FROM emp ORDER BY dept_id, title;\nSELECT DISTINCT salary FROM emp;\n"
    )
    add(
        var cs, "aggregates",
        "SELECT COUNT(*), COUNT(salary), COUNT(title), SUM(salary), MIN(salary), MAX(salary), MIN(name), MAX(name) FROM emp;\nSELECT COUNT(DISTINCT dept_id), COUNT(DISTINCT salary), COUNT(DISTINCT title) FROM emp;\nSELECT COUNT(*), SUM(salary), MAX(name) FROM emp WHERE id > 100;\nSELECT SUM(salary) + 1, COUNT(*) * 2, ABS(MIN(salary) - 100) FROM emp;\nSELECT COUNT(*) AS n FROM emp WHERE dept_id = 1;\nSELECT SUM(DISTINCT salary) FROM emp;\n"
    )
    add(
        var cs, "group-by",
        "SELECT dept_id, COUNT(*), SUM(salary), MAX(salary) FROM emp GROUP BY dept_id ORDER BY dept_id;\nSELECT dept_id, title, COUNT(*) AS n FROM emp GROUP BY dept_id, title ORDER BY n DESC, dept_id, title;\nSELECT title, COUNT(*) FROM emp GROUP BY title;\nSELECT dept_id FROM emp GROUP BY dept_id HAVING COUNT(*) >= 2 ORDER BY dept_id;\nSELECT dept_id, SUM(salary) AS total FROM emp GROUP BY dept_id HAVING SUM(salary) > 150 ORDER BY total DESC;\nSELECT COUNT(*) FROM emp HAVING COUNT(*) > 100;\nSELECT COUNT(*) FROM emp HAVING COUNT(*) > 1;\nSELECT dept_id, COUNT(*) FROM emp WHERE salary IS NOT NULL GROUP BY dept_id ORDER BY 2 DESC, 1;\nSELECT dept_id FROM emp WHERE id > 100 GROUP BY dept_id;\n"
    )
    add(
        var cs, "group-by-rules",
        "SELECT name, COUNT(*) FROM emp GROUP BY dept_id;\nSELECT dept_id, name FROM emp GROUP BY dept_id;\nSELECT name, COUNT(*) FROM emp;\nSELECT dept_id FROM emp GROUP BY dept_id ORDER BY name;\nSELECT dept_id FROM emp GROUP BY nope;\nSELECT dept_id, COUNT(*) FROM emp GROUP BY dept_id ORDER BY COUNT(*) DESC, dept_id;\nSELECT SUM(salary) FROM emp GROUP BY dept_id ORDER BY dept_id;\nSELECT dept_id + 1 FROM emp GROUP BY dept_id;\n"
    )
    add(
        var cs, "inner-join",
        "SELECT emp.name, dept.name FROM emp JOIN dept ON emp.dept_id = dept.id ORDER BY emp.id;\nSELECT e.name, d.city FROM emp e INNER JOIN dept AS d ON e.dept_id = d.id WHERE d.city IS NOT NULL ORDER BY e.name;\nSELECT d.name, COUNT(*) AS n, SUM(e.salary) FROM dept d JOIN emp e ON e.dept_id = d.id GROUP BY d.name ORDER BY n DESC, d.name;\nSELECT * FROM dept d JOIN emp e ON d.id = e.dept_id WHERE e.id = 1;\nSELECT d.* FROM dept d JOIN emp e ON d.id = e.dept_id AND e.salary > 99 ORDER BY d.id, e.id;\nSELECT e.name FROM emp e JOIN emp m ON e.salary = m.salary AND e.id < m.id;\n"
    )
    add(
        var cs, "left-join",
        "SELECT d.name, e.name FROM dept d LEFT JOIN emp e ON e.dept_id = d.id ORDER BY d.id, e.id;\nSELECT d.name, COUNT(e.id) FROM dept d LEFT JOIN emp e ON e.dept_id = d.id GROUP BY d.name ORDER BY d.name;\nSELECT e.name FROM emp e LEFT JOIN dept d ON e.dept_id = d.id WHERE d.id IS NULL ORDER BY e.id;\nSELECT d.name FROM dept d LEFT JOIN emp e ON e.dept_id = d.id AND e.salary > 1000 ORDER BY d.id;\nSELECT COUNT(*) FROM emp e LEFT JOIN dept d ON 1 = 1;\n"
    )
    add(
        var cs, "multi-join",
        "CREATE TABLE proj (id INT PRIMARY KEY, name TEXT, dept_id INT);\nCREATE TABLE assign (emp_id INT, proj_id INT, hours INT);\nINSERT INTO proj VALUES (10, 'Apollo', 1), (11, 'Zeus', 2), (12, 'Hermes', 1);\nINSERT INTO assign VALUES (1, 10, 5), (2, 10, 8), (2, 12, 3), (3, 11, 9), (7, 12, 4), (7, 10, 1);\nSELECT e.name, p.name, a.hours FROM assign a JOIN emp e ON a.emp_id = e.id JOIN proj p ON a.proj_id = p.id ORDER BY e.name, p.name;\nSELECT p.name, SUM(a.hours) AS h, COUNT(*) AS n FROM proj p LEFT JOIN assign a ON a.proj_id = p.id GROUP BY p.name ORDER BY h DESC, p.name;\nSELECT e.name, d.name, p.name FROM emp e JOIN dept d ON e.dept_id = d.id LEFT JOIN proj p ON p.dept_id = d.id WHERE e.id <= 3 ORDER BY e.id, p.id;\nSELECT DISTINCT d.name FROM dept d JOIN proj p ON p.dept_id = d.id ORDER BY 1;\n"
    )
    add(
        var cs, "functions",
        "SELECT UPPER(name), LOWER(name), LENGTH(name) FROM emp WHERE id <= 2;\nSELECT COALESCE(title, 'none'), COALESCE(NULL, NULL, 7), COALESCE(salary, 0) FROM emp WHERE id IN (5, 8);\nSELECT SUBSTR('hello world', 1, 5), SUBSTR('hello', 2, 100), SUBSTR('hello', 0, 3), SUBSTR('hello', -1, 4), SUBSTR('hello', 6, 1), SUBSTR('hello', 2, 0), SUBSTR(NULL, 1, 1);\nSELECT ABS(-5), ABS(5), ABS(NULL), LENGTH(NULL), UPPER('abc' || 'def');\nSELECT name FROM emp WHERE LENGTH(name) = 3 ORDER BY name;\nselect upper('x'), Lower('Y'), abs(-1), count(*) from emp;\n"
    )
    add(
        var cs, "keywords-case",
        "select Name from emp;\nselect name from EMP;\nSeLeCt name FrOm emp WhErE id = 1;\nSELECT e.name FROM emp e WHERE e.id = 1;\nSELECT E.name FROM emp e WHERE e.id = 1;\ncreate table T (A int primary key, B text);\ninsert into T values (1, 'x');\nselect A, B from T;\n"
    )
    add(
        var cs, "alias-names",
        "SELECT name AS n, salary s, id + 1 FROM emp WHERE id = 1;\nSELECT name n, salary AS name FROM emp WHERE id = 2;\nSELECT 1 AS one, 2 AS one;\nSELECT e.name, d.name FROM emp e JOIN dept d ON e.dept_id = d.id WHERE e.id = 1;\nSELECT COUNT(*), COUNT(*) AS c FROM emp;\n"
    )
    add(
        var cs, "insert-forms",
        "CREATE TABLE t (a INT, b TEXT, c INT NOT NULL);\nINSERT INTO t (c, a) VALUES (1, 2);\nINSERT INTO t (b, c) VALUES ('x', 3), ('y', 4);\nINSERT INTO t VALUES (1, 'z', 2 + 3);\nINSERT INTO t (c) VALUES (-5);\nINSERT INTO t (a, b) VALUES (1, 'q');\nSELECT * FROM t;\nINSERT INTO t VALUES (1, 'q');\nINSERT INTO t (a, a, c) VALUES (1, 2, 3);\nINSERT INTO t (a, zz, c) VALUES (1, 2, 3);\nINSERT INTO t VALUES ('s', 'x', 1);\nINSERT INTO t VALUES (1, 2, 3);\nINSERT INTO t VALUES (1, 'it''s', 3);\nSELECT b FROM t WHERE a = 1 ORDER BY b;\nINSERT INTO t VALUES (z, 'q', 1);\nINSERT INTO nope VALUES (1);\nINSERT INTO t VALUES (COUNT(*), 'q', 1);\nSELECT COUNT(*) FROM t;\n",
        setup: false
    )
    add(
        var cs, "constraints",
        "SELECT COUNT(*) FROM emp;\nINSERT INTO emp VALUES (1, 'Dup', 1, 1, 'x');\nINSERT INTO emp VALUES (20, 'Ok', 1, 1, 'x'), (20, 'Twice', 1, 1, 'x');\nINSERT INTO emp VALUES (NULL, 'NoId', 1, 1, 'x');\nINSERT INTO emp VALUES (21, NULL, 1, 1, 'x');\nSELECT COUNT(*) FROM emp;\nUPDATE emp SET id = 2 WHERE id = 3;\nUPDATE emp SET name = NULL WHERE id = 3;\nUPDATE emp SET id = id + 100;\nSELECT id FROM emp ORDER BY id LIMIT 2;\nUPDATE emp SET id = id - 100;\nUPDATE emp SET salary = 'rich' WHERE id = 1;\nUPDATE emp SET id = 1000 WHERE id = 1;\nUPDATE emp SET id = id + 1 WHERE id = 1000;\nSELECT id, name FROM emp WHERE id > 999;\n"
    )
    add(
        var cs, "update-forms",
        "UPDATE emp SET salary = salary * 2 WHERE dept_id = 1;\nSELECT name, salary FROM emp WHERE dept_id = 1 ORDER BY id;\nUPDATE emp SET title = 'x', salary = 1 WHERE id = 5;\nSELECT * FROM emp WHERE id = 5;\nUPDATE emp SET salary = salary + 1;\nSELECT SUM(salary) FROM emp;\nUPDATE emp SET name = name || '!' WHERE name LIKE 'A%';\nUPDATE emp SET salary = id, id = salary WHERE id = 2;\nUPDATE emp SET salary = 0 WHERE id > 1000;\nUPDATE emp SET nope = 1;\nUPDATE emp SET salary = nope;\nUPDATE nope SET a = 1;\nUPDATE emp SET salary = 1 WHERE nope = 1;\nUPDATE emp SET salary = COUNT(*);\nUPDATE emp SET salary = 1 / 0 WHERE id = 1;\nSELECT salary FROM emp WHERE id = 1;\n"
    )
    add(
        var cs, "delete-forms",
        "DELETE FROM emp WHERE dept_id = 3;\nSELECT COUNT(*) FROM emp;\nDELETE FROM emp WHERE dept_id = NULL;\nDELETE FROM emp WHERE salary > 1000;\nDELETE FROM emp;\nSELECT * FROM emp;\nDELETE FROM nope;\nDELETE FROM dept WHERE nope = 1;\nINSERT INTO emp VALUES (1, 'New', 1, 1, 'x');\nSELECT name FROM emp;\n"
    )
    add(
        var cs, "drop-create-errors",
        "CREATE TABLE emp (a INT);\nDROP TABLE emp;\nDROP TABLE emp;\nCREATE TABLE emp (a INT, a TEXT);\nCREATE TABLE emp (a INT PRIMARY KEY, b INT PRIMARY KEY);\nCREATE TABLE emp (a FLOAT);\nCREATE TABLE emp (a INT, b TEXT NOT NULL PRIMARY KEY NOT NULL);\nSELECT * FROM emp;\nINSERT INTO emp VALUES (1, 'x');\nINSERT INTO emp VALUES (1, 'y');\nCREATE TABLE select (a INT);\nCREATE TABLE emp2 ();\nCREATE TABLE ();\n",
        setup: false
    )
    add(
        var cs, "name-errors",
        "SELECT nope FROM emp;\nSELECT emp.nope FROM emp;\nSELECT x.name FROM emp;\nSELECT name FROM nope;\nSELECT id FROM emp JOIN dept ON emp.dept_id = dept.id;\nSELECT emp.id FROM emp JOIN dept ON emp.dept_id = dept.id LIMIT 1;\nSELECT name FROM emp JOIN dept ON emp.dept_id = dept.id LIMIT 1;\nSELECT e.name FROM emp e JOIN emp e ON e.id = e.id;\nSELECT a.name FROM emp a JOIN emp b ON a.id = b.id WHERE b.id = 1;\nSELECT name FROM emp a JOIN emp b ON a.id = b.id;\nSELECT z.* FROM emp;\nSELECT * FROM emp JOIN dept ON emp.dept_id = nope.id;\nSELECT * FROM emp JOIN dept ON emp.dept_id = dept.nope;\nSELECT * FROM emp JOIN nope ON 1 = 1;\nSELECT FOO(1);\nSELECT UPPER('a', 'b');\nSELECT UPPER();\nSELECT SUBSTR('a', 1);\nSELECT COALESCE();\nSELECT SUM(1, 2);\nSELECT SUM();\nSELECT COUNT(*) FROM emp WHERE COUNT(*) > 1;\nSELECT SUM(COUNT(*)) FROM emp;\nSELECT * FROM emp JOIN dept ON COUNT(*) > 1;\nSELECT nope.* FROM emp e;\nSELECT 1 FROM emp ORDER BY 5;\nSELECT 1 FROM emp ORDER BY 0;\n"
    )
    add(
        var cs, "type-errors",
        "SELECT 1 + 'a';\nSELECT 'a' + 'b';\nSELECT 'a' * 2;\nSELECT -'a';\nSELECT 1 || 2;\nSELECT 1 = 'a';\nSELECT 'a' < 1;\nSELECT 1 AND 2;\nSELECT NOT 5;\nSELECT 1 OR NULL;\nSELECT 'x' LIKE 5;\nSELECT 5 LIKE 'x';\nSELECT UPPER(5);\nSELECT ABS('a');\nSELECT SUM('a');\nSELECT 1 FROM emp WHERE 1;\nSELECT 1 FROM emp WHERE name;\nSELECT MAX(name) FROM emp WHERE id < 0;\nSELECT 1 IN ('a');\nSELECT (1 < 2) = (2 < 3);\nSELECT 1 BETWEEN 'a' AND 2;\nSELECT 1 / 0;\nSELECT 1 % 0;\nSELECT 1 / 0 FROM emp WHERE id > 100;\nSELECT SUBSTR('abc', 'a', 1);\nSELECT NULL + 1, NULL || 'a', -NULL, 1 / NULL;\nSELECT false = true;\n"
    )
    add(
        var cs, "short-circuit",
        "SELECT 1 = 2 AND 1 / 0 = 1;\nSELECT 1 = 1 OR 1 / 0 = 1;\nSELECT 1 = 1 AND 1 / 0 = 1;\nSELECT 1 = 2 OR 1 / 0 = 1;\nSELECT NULL AND 1 / 0 = 1;\nSELECT COALESCE(1, 1 / 0);\n",
        setup: false
    )
    add(
        var cs, "syntax-errors",
        "SELEC 1;\nSELECT;\nSELECT 1 +;\nSELECT * FORM emp;\nSELECT * FROM;\nSELECT * FROM emp WHERE;\nSELECT (1;\nSELECT 1 2;\nSELECT 'abc;\nSELECT 1 # 2;\nSELECT * FROM emp LIMIT x;\nSELECT * FROM emp LIMIT -1;\nSELECT * FROM emp OFFSET 1;\nSELECT * FROM emp GROUP name;\nSELECT * FROM emp GROUP BY name + 1;\nSELECT * FROM emp ORDER name;\nSELECT * FROM emp ORDER BY;\nSELECT * FROM emp JOIN dept;\nSELECT * FROM emp JOIN dept ON;\nSELECT * FROM emp LEFT dept ON 1 = 1;\nINSERT emp VALUES (1);\nINSERT INTO emp VALUES;\nINSERT INTO emp VALUES (1,);\nINSERT INTO emp VALUES ();\nINSERT INTO emp () VALUES (1);\nUPDATE emp salary = 1;\nUPDATE emp SET;\nUPDATE emp SET salary 1;\nDELETE emp;\nDELETE FROM;\nDROP emp;\nCREATE emp (a INT);\nSELECT a FROM emp WHERE id IN ();\nSELECT a FROM emp WHERE id IN 1;\nSELECT COUNT(*, 1) FROM emp;\nSELECT SUM(*) FROM emp;\nSELECT COUNT(DISTINCT *) FROM emp;\nSELECT COUNT(DISTINCT id, name) FROM emp;\nSELECT 1 FROM emp WHERE id BETWEEN 1;\nSELECT 1 FROM emp WHERE id = = 1;\nSELECT 1 FROM emp WHERE id < 2 < 3;\nSELECT 1 FROM emp WHERE 1 = 1 = 1;\nSELECT * emp;\nSELECT 1; SELECT 2 3;\nFOO;\n123;\n"
    )
    add(
        var cs, "syntax-vs-semantic",
        "SELECT nope FROM emp WHERE;\nSELECT nope FROM nope2 ORDER;\nINSERT INTO nope VALUES (1,);\nUPDATE nope SET a = ;\nDELETE FROM nope WHERE;\n"
    )
    add(
        var cs, "statement-splitting",
        "SELECT ';' AS semi;\nSELECT 'a;b';\n-- comment; with semi\nSELECT 1; -- trailing\n  ;;\n\n;SELECT 2\n;\nSELECT 'it''s; fine' -- c\n;\nSELECT 3",
        setup: false
    )
    add(
        var cs, "comments",
        "-- leading comment\nSELECT /* not a comment */ 1;\nSELECT 1 -- x\n  + 2;\nSELECT '--not a comment';\n-- only comment",
        setup: false
    )
    add(
        var cs, "precedence",
        "SELECT 1 + 2 * 3 - 4 / 2, (1 + 2) * 3, 2 * 3 % 4, 10 - 2 - 3, 100 / 10 / 5, -2 * -3, - - 2;\nSELECT 'a' || 'b' || 'c', 'x' || 'y' = 'xy';\nSELECT 1 < 2 AND 2 < 3 OR 1 = 0, NOT 1 = 2 AND 1 = 1, 1 + 1 = 2 AND 'a' || 'b' = 'ab';\nSELECT 1 = 1 = 1;\nSELECT 5 BETWEEN 1 + 1 AND 2 * 3, 5 NOT BETWEEN 1 AND 3 AND 1 = 1;\nSELECT 2 IN (1 + 1, 3) AND 2 NOT IN (3, 4);\nSELECT 7 / 2, -7 / 2, 7 / -2, 7 % 2, -7 % 2;\n",
        setup: false
    )
    add(
        var cs, "order-null-mixed",
        "CREATE TABLE m (k INT, v TEXT);\nINSERT INTO m VALUES (3, 'c'), (NULL, 'n'), (1, NULL), (2, 'b'), (NULL, 'a'), (1, 'a');\nSELECT * FROM m ORDER BY k;\nSELECT * FROM m ORDER BY k DESC, v;\nSELECT * FROM m ORDER BY v, k DESC;\nSELECT k, COUNT(*), MAX(v), MIN(v) FROM m GROUP BY k ORDER BY k;\nSELECT DISTINCT k FROM m ORDER BY k DESC;\nSELECT COALESCE(v, '?') AS w FROM m ORDER BY w;\nSELECT * FROM m WHERE k > 1 OR v IS NULL ORDER BY 1, 2;\nSELECT * FROM m ORDER BY k LIMIT 2 OFFSET 1;\nSELECT COUNT(DISTINCT k), COUNT(k), COUNT(*) FROM m;\n",
        setup: false
    )
    add(
        var cs, "text-values",
        "CREATE TABLE s (v TEXT);\nINSERT INTO s VALUES (''), (' '), ('A'), ('a'), ('ab'), ('B'), ('10'), ('9'), ('a|b'), ('x y');\nSELECT v FROM s ORDER BY v;\nSELECT v, LENGTH(v) FROM s WHERE v < 'a' ORDER BY v;\nSELECT COUNT(*) FROM s WHERE v LIKE '%';\nSELECT v FROM s WHERE v LIKE '_' ORDER BY v;\nSELECT v FROM s WHERE v LIKE 'a%b' OR v LIKE '%|%' ORDER BY v;\nSELECT MIN(v), MAX(v) FROM s;\nSELECT v FROM s WHERE v = '' OR v = ' ';\nSELECT v || v FROM s WHERE LENGTH(v) = 2 ORDER BY 1;\n",
        setup: false
    )
    add(
        var cs, "scalar-subset-having",
        "SELECT dept_id, COUNT(*) AS n FROM emp GROUP BY dept_id HAVING n > 1;\nSELECT dept_id, COUNT(*) AS n FROM emp GROUP BY dept_id HAVING COUNT(*) > 1 AND dept_id IS NOT NULL ORDER BY n DESC, dept_id;\nSELECT dept_id FROM emp GROUP BY dept_id HAVING dept_id = 1;\nSELECT dept_id FROM emp GROUP BY dept_id HAVING name = 'x';\nSELECT dept_id FROM emp HAVING dept_id = 1;\n"
    )
    add(
        var cs,
        "big-aggregate",
        big
        + "SELECT COUNT(*), SUM(qty), MIN(price), MAX(price), COUNT(note) FROM sales;\nSELECT region, COUNT(*) AS n, SUM(qty * price) AS revenue FROM sales GROUP BY region ORDER BY revenue DESC;\nSELECT item, region, SUM(qty) AS q FROM sales GROUP BY item, region HAVING SUM(qty) > 25 ORDER BY q DESC, item, region;\nSELECT note, COUNT(*) FROM sales GROUP BY note ORDER BY note;\nSELECT region, item FROM sales WHERE qty > 10 AND price < 20 ORDER BY region, item, id LIMIT 10;\nSELECT DISTINCT item FROM sales WHERE region = 'north' ORDER BY item;\nSELECT id, qty * price AS total FROM sales ORDER BY total DESC, id LIMIT 5;\n",
        setup: false
    )
    add(
        var cs,
        "big-mutations",
        big
        + "UPDATE sales SET price = price + 1 WHERE region = 'east';\nDELETE FROM sales WHERE qty < 3;\nSELECT COUNT(*), SUM(price) FROM sales;\nUPDATE sales SET note = 'bulk' WHERE note IS NULL;\nSELECT note, COUNT(*) FROM sales GROUP BY note ORDER BY 1;\nDELETE FROM sales WHERE id % 2 = 0;\nSELECT COUNT(*), MIN(id), MAX(id) FROM sales;\nSELECT id FROM sales ORDER BY id LIMIT 5;\n",
        setup: false
    )
    add(
        var cs,
        "big-join",
        big
        + "CREATE TABLE regions (name TEXT PRIMARY KEY, manager TEXT);\nINSERT INTO regions VALUES ('north', 'Ng'), ('south', 'Sy'), ('east', 'Ea'), ('central', 'Ce');\nSELECT r.manager, COUNT(s.id) AS n, SUM(s.qty) FROM regions r LEFT JOIN sales s ON s.region = r.name GROUP BY r.manager ORDER BY r.manager;\nSELECT s.region, r.manager FROM sales s LEFT JOIN regions r ON r.name = s.region WHERE r.name IS NULL AND s.id < 30 ORDER BY s.id;\nSELECT a.id, b.id FROM sales a JOIN sales b ON a.item = b.item AND a.region = b.region AND a.id < b.id WHERE a.id < 8 ORDER BY a.id, b.id LIMIT 12;\n",
        setup: false
    )
    add(var cs, "empty-and-whitespace", "", setup: false)
    add(
        var cs, "only-errors", "FOO BAR;\nSELECT * FROM x;\nSELECT 1 +;\n", setup: false
    )
    add(
        var cs, "no-trailing-semicolon",
        "CREATE TABLE a (x INT);\nINSERT INTO a VALUES (1), (2)\n;\nSELECT SUM(x) FROM a",
        setup: false
    )

    let examples = [
        cs.make(
            "basic",
            SETUP
            + "SELECT name, salary FROM emp WHERE salary > 95 ORDER BY name;\nSELECT d.name, COUNT(*) AS n FROM dept d JOIN emp e ON e.dept_id = d.id GROUP BY d.name ORDER BY n DESC, d.name;\nUPDATE emp SET salary = salary + 5 WHERE dept_id = 2;\nSELECT name, salary FROM emp WHERE dept_id = 2;\n"
        ),
        cs.make(
            "errors",
            "CREATE TABLE t (a INT PRIMARY KEY, b TEXT);\nINSERT INTO t VALUES (1, 'x');\nINSERT INTO t VALUES (1, 'y');\nSELECT c FROM t;\nSELECT * FROM nope;\nSELECT 1 +;\nSELECT a, b FROM t;\n"
        ),
        cs.make(
            "left-join-null",
            SETUP
            + "SELECT d.name, e.name FROM dept d LEFT JOIN emp e ON e.dept_id = d.id AND e.salary > 100 ORDER BY d.id;\nSELECT title, COUNT(*), SUM(salary) FROM emp GROUP BY title ORDER BY title;\n"
        )
    ]
    write_cases("c52-sql-engine", examples, examples.concat(cs.list))
