package main

import (
	"regexp"
	"strconv"
	"strings"

	rt "github.com/manuscript-lang/manuscript/pkg/runtime"
)

// captureTransport records the bytes a logger writes.
type captureTransport struct{ data []byte }

func (c *captureTransport) Write(_ *rt.Execution, s string) rt.Result[rt.Unit, rt.LogError] {
	c.data = append(c.data, s...)
	return rt.Ok[rt.Unit, rt.LogError](rt.Unit{})
}

func (c *captureTransport) WriteBytes(_ *rt.Execution, b *rt.Bytes) rt.Result[rt.Unit, rt.LogError] {
	c.data = append(c.data, b.Data...)
	return rt.Ok[rt.Unit, rt.LogError](rt.Unit{})
}

func (c *captureTransport) Flush(*rt.Execution) rt.Result[rt.Unit, rt.LogError] {
	return rt.Ok[rt.Unit, rt.LogError](rt.Unit{})
}

func (c *captureTransport) Close(*rt.Execution) rt.Unit { return rt.Unit{} }

var logLevels = []rt.LogLevel{rt.LogLevel_Trace{}, rt.LogLevel_Debug{}, rt.LogLevel_Info{}, rt.LogLevel_Warn{}, rt.LogLevel_Error{}, rt.LogLevel_Fatal{}, rt.LogLevel_Silent{}}

var logTime = regexp.MustCompile(`"time":[0-9]+`)

func logErrName(e rt.LogError) string { return errName(e) }

// logCase records one logger configuration, its child bindings and one record.
func logCase(r *recorder, cfg []string, bindings []string, level int, msg, fields string) {
	var lv rt.Option[rt.LogLevel]
	if cfg[0] != "-" {
		n, _ := strconv.Atoi(cfg[0])
		lv = rt.Some(logLevels[n])
	}
	var ts rt.Option[bool]
	if cfg[1] != "-" {
		ts = rt.Some(cfg[1] == "1")
	}
	var mx rt.Option[int]
	if cfg[2] != "-" {
		n, _ := strconv.Atoi(cfg[2])
		mx = rt.Some(n)
	}
	head := []string{"rec", cfg[0], cfg[1], cfg[2], strconv.Itoa(len(bindings))}
	for _, b := range bindings {
		head = append(head, h(b))
	}
	head = append(head, strconv.Itoa(level), h(msg), fieldsToken(fields))
	tr := &captureTransport{}
	created := rt.Log_Create(nil, tr, lv, ts, mx)
	if created.Failed {
		r.row(append(head, "=>", "err "+logErrName(created.Err))...)
		return
	}
	logger := created.Val
	for _, b := range bindings {
		child := logger.ChildJson(nil, b)
		if child.Failed {
			r.row(append(head, "=>", "err "+logErrName(child.Err))...)
			return
		}
		logger = child.Val
	}
	var res rt.Result[rt.Unit, rt.LogError]
	if fields == "\x00" {
		res = logger.Log(nil, logLevels[level], msg)
	} else {
		res = logger.LogJson(nil, logLevels[level], msg, fields)
	}
	switch {
	case res.Failed:
		r.row(append(head, "=>", "err "+logErrName(res.Err))...)
	case len(tr.data) == 0:
		r.row(append(head, "=>", "ok none")...)
	default:
		line := logTime.ReplaceAllString(string(tr.data), `"time":0`)
		r.row(append(head, "=>", "ok "+h(line))...)
	}
}

func fieldsToken(f string) string {
	if f == "\x00" {
		return "-"
	}
	return h(f)
}

func genLog(dir string) {
	r := &recorder{}
	fieldsList := []string{"\x00", `{}`, `{"a":1}`, `{"level":1,"msg":2,"time":3,"x":[1,2,{"y":null}]}`, `[1]`, `1`, `nul`, `{"a":1,"a":2}`, `{"k":"<>& é"}`, `{"n":1e400}`, `"s"`, ` {"p": true} `, `{"a":1} x`}
	bindingSets := [][]string{nil, {`{"a":1,"b":2}`}, {`{"a":1}`, `{"a":9,"c":[true]}`}, {`[1]`}, {`{"time":5,"level":"x"}`}}
	msgs := []string{"", "hello", "a<b>&\"\n\t\u0001é"}
	cfgs := [][]string{{"-", "-", "-"}, {"0", "0", "-"}, {"3", "1", "1000"}, {"2", "0", "40"}, {"-", "0", "0"}, {"-", "0", "-1"}}
	i := 0
	for _, cfg := range cfgs {
		for _, b := range bindingSets {
			for _, f := range fieldsList {
				for _, level := range []int{0, 2, 4, 6} {
					logCase(r, cfg, b, level, msgs[i%len(msgs)], f)
					i++
				}
			}
		}
	}
	// Line-size boundaries.
	for max := 0; max <= 70; max++ {
		for _, f := range []string{"\x00", `{"a":"xyz","b":[1,2]}`} {
			logCase(r, []string{"0", "0", strconv.Itoa(max)}, []string{`{"c":"<"}`}, 3, "m", f)
		}
	}
	// Level index and thresholds with timestamps on.
	for lv := 0; lv <= 6; lv++ {
		for level := 0; level <= 6; level++ {
			logCase(r, []string{strconv.Itoa(lv), "1", "-"}, nil, level, "t", `{"z":0}`)
		}
	}
	_ = strings.TrimSpace
	r.write(dir, "log.tsv")
}
