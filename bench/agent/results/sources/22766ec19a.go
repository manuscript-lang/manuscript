package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"sort"
	"strconv"
	"strings"
)

const overdraftFee int64 = 5

type account struct {
	id       string
	balance  int64
	limit    int64
	ops      int64
	rejected int64
	frozen   bool
}

type ledger struct {
	accounts map[string]*account
	fees     int64
	out      *bufio.Writer
}

func main() {
	l := &ledger{accounts: make(map[string]*account)}
	l.out = bufio.NewWriter(os.Stdout)
	defer l.out.Flush()

	reader := bufio.NewReader(os.Stdin)
	for {
		line, err := reader.ReadString('\n')
		if len(line) > 0 || err == nil {
			l.handleLine(strings.TrimSuffix(line, "\n"))
		}
		if err != nil {
			if err != io.EOF {
				fmt.Fprintln(os.Stderr, err)
			}
			break
		}
	}
}

// tokenize splits on runs of spaces and tabs. A trailing carriage return
// (from CRLF input) is ignored.
func tokenize(line string) []string {
	line = strings.TrimSuffix(line, "\r")
	return strings.FieldsFunc(line, func(r rune) bool {
		return r == ' ' || r == '\t'
	})
}

// parseDigits reports whether s is a non-empty string of ASCII digits and
// returns its value. Values are assumed to fit in int64 per the spec.
func parseDigits(s string) (int64, bool) {
	if s == "" {
		return 0, false
	}
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			return 0, false
		}
	}
	v, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		return 0, false
	}
	return v, true
}

// parseAmount returns the amount if it is a digit string with value > 0.
func parseAmount(s string) (int64, bool) {
	v, ok := parseDigits(s)
	if !ok || v <= 0 {
		return 0, false
	}
	return v, true
}

func (l *ledger) say(s string) {
	l.out.WriteString(s)
	l.out.WriteByte('\n')
}

func (l *ledger) blame(a *account) {
	a.rejected++
}

func (l *ledger) handleLine(line string) {
	tok := tokenize(line)
	if len(tok) == 0 {
		return
	}
	switch tok[0] {
	case "open":
		l.cmdOpen(tok)
	case "deposit":
		l.cmdDeposit(tok)
	case "withdraw":
		l.cmdWithdraw(tok)
	case "transfer":
		l.cmdTransfer(tok)
	case "freeze":
		l.cmdFreeze(tok, true)
	case "unfreeze":
		l.cmdFreeze(tok, false)
	case "report":
		if len(tok) != 1 {
			l.say("error: bad command")
			return
		}
		l.cmdReport()
	default:
		l.say("error: bad command")
	}
}

func (l *ledger) cmdOpen(tok []string) {
	if len(tok) != 3 {
		l.say("error: bad command")
		return
	}
	id := tok[1]
	limit, ok := parseDigits(tok[2])
	if !ok {
		l.say("error: invalid limit")
		return
	}
	if _, exists := l.accounts[id]; exists {
		l.say("error: account exists " + id)
		return
	}
	l.accounts[id] = &account{id: id, limit: limit}
	l.say("ok")
}

func (l *ledger) cmdFreeze(tok []string, frozen bool) {
	if len(tok) != 2 {
		l.say("error: bad command")
		return
	}
	a, ok := l.accounts[tok[1]]
	if !ok {
		l.say("error: unknown account " + tok[1])
		return
	}
	a.frozen = frozen
	l.say("ok")
}

// debit applies a withdrawal of amt to a, including the overdraft fee rule.
// It returns the fee charged, and false (with the error line already
// written and the account blamed) if the command must fail.
func (l *ledger) debit(a *account, amt int64) (int64, bool) {
	newBal := a.balance - amt
	var fee int64
	if a.balance >= 0 && newBal < 0 {
		fee = overdraftFee
		newBal -= fee
	}
	if newBal < -a.limit {
		l.blame(a)
		l.say("error: overdraft limit exceeded " + a.id)
		return 0, false
	}
	a.balance = newBal
	l.fees += fee
	return fee, true
}

func feeSuffix(fee int64) string {
	if fee != 0 {
		return " fee=" + strconv.FormatInt(fee, 10)
	}
	return ""
}

func (l *ledger) cmdDeposit(tok []string) {
	if len(tok) != 3 {
		l.say("error: bad command")
		return
	}
	a, ok := l.accounts[tok[1]]
	if !ok {
		l.say("error: unknown account " + tok[1])
		return
	}
	amt, ok := parseAmount(tok[2])
	if !ok {
		l.blame(a)
		l.say("error: invalid amount")
		return
	}
	if a.frozen {
		l.blame(a)
		l.say("error: account frozen " + a.id)
		return
	}
	a.balance += amt
	a.ops++
	l.say("ok " + strconv.FormatInt(a.balance, 10))
}

func (l *ledger) cmdWithdraw(tok []string) {
	if len(tok) != 3 {
		l.say("error: bad command")
		return
	}
	a, ok := l.accounts[tok[1]]
	if !ok {
		l.say("error: unknown account " + tok[1])
		return
	}
	amt, ok := parseAmount(tok[2])
	if !ok {
		l.blame(a)
		l.say("error: invalid amount")
		return
	}
	if a.frozen {
		l.blame(a)
		l.say("error: account frozen " + a.id)
		return
	}
	fee, ok := l.debit(a, amt)
	if !ok {
		return
	}
	a.ops++
	l.say("ok " + strconv.FormatInt(a.balance, 10) + feeSuffix(fee))
}

func (l *ledger) cmdTransfer(tok []string) {
	if len(tok) != 4 {
		l.say("error: bad command")
		return
	}
	from, ok := l.accounts[tok[1]]
	if !ok {
		l.say("error: unknown account " + tok[1])
		return
	}
	to, ok := l.accounts[tok[2]]
	if !ok {
		l.say("error: unknown account " + tok[2])
		return
	}
	if from == to {
		l.blame(from)
		l.say("error: same account")
		return
	}
	amt, ok := parseAmount(tok[3])
	if !ok {
		l.blame(from)
		l.say("error: invalid amount")
		return
	}
	if from.frozen {
		l.blame(from)
		l.say("error: account frozen " + from.id)
		return
	}
	if to.frozen {
		l.blame(to)
		l.say("error: account frozen " + to.id)
		return
	}
	fee, ok := l.debit(from, amt)
	if !ok {
		return
	}
	to.balance += amt
	from.ops++
	to.ops++
	l.say("ok " + strconv.FormatInt(from.balance, 10) + " " +
		strconv.FormatInt(to.balance, 10) + feeSuffix(fee))
}

func (l *ledger) cmdReport() {
	ids := make([]string, 0, len(l.accounts))
	for id := range l.accounts {
		ids = append(ids, id)
	}
	sort.Strings(ids)

	var total int64
	for _, id := range ids {
		a := l.accounts[id]
		total += a.balance
		frozen := "no"
		if a.frozen {
			frozen = "yes"
		}
		l.say(fmt.Sprintf("%s balance=%d limit=%d ops=%d rejected=%d frozen=%s",
			a.id, a.balance, a.limit, a.ops, a.rejected, frozen))
	}
	l.say(fmt.Sprintf("total balance=%d fees=%d", total, l.fees))
}
