package balance

import (
	"context"
	"io"
	"net"
	"strings"
	"testing"
	"time"
)

func listener(t *testing.T) net.Listener {
	t.Helper()
	ln, e := net.Listen("tcp", "127.0.0.1:0")
	if e != nil {
		t.Fatal(e)
	}
	t.Cleanup(func() { ln.Close() })
	return ln
}
func backend(t *testing.T, prefix string) string {
	t.Helper()
	ln := listener(t)
	go func() {
		for {
			c, e := ln.Accept()
			if e != nil {
				return
			}
			go func() {
				defer c.Close()
				c.SetDeadline(time.Now().Add(3 * time.Second))
				b, e := io.ReadAll(c)
				if e == nil {
					io.WriteString(c, prefix+string(b))
				}
			}()
		}
	}()
	return ln.Addr().String()
}
func start(t *testing.T, targets []string, max, drain int) (*Server, string, context.CancelFunc, <-chan error) {
	t.Helper()
	ln := listener(t)
	s, e := New(Config{"l4load.dev/v0alpha1", ln.Addr().String(), targets, max, 200, 2000, drain})
	if e != nil {
		t.Fatal(e)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- s.Serve(ctx, ln) }()
	t.Cleanup(cancel)
	return s, ln.Addr().String(), cancel, done
}
func request(t *testing.T, addr string) string {
	t.Helper()
	c, e := net.DialTimeout("tcp", addr, time.Second)
	if e != nil {
		t.Fatal(e)
	}
	defer c.Close()
	c.SetDeadline(time.Now().Add(3 * time.Second))
	if _, e = io.WriteString(c, "payload"); e != nil {
		t.Fatal(e)
	}
	if e = c.(*net.TCPConn).CloseWrite(); e != nil {
		t.Fatal(e)
	}
	b, e := io.ReadAll(c)
	if e != nil {
		t.Fatal(e)
	}
	return string(b)
}
func stopped(t *testing.T, done <-chan error) {
	t.Helper()
	select {
	case e := <-done:
		if e != nil {
			t.Fatal(e)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("server failed to stop")
	}
}
func eventually(t *testing.T, f func() bool) {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		if f() {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("condition not reached")
}

func TestRoundRobinAndHalfClose(t *testing.T) {
	a, b := backend(t, "a:"), backend(t, "b:")
	s, addr, cancel, done := start(t, []string{a, b}, 8, 200)
	for _, want := range []string{"a:payload", "b:payload", "a:payload", "b:payload"} {
		if got := request(t, addr); got != want {
			t.Fatalf("got %q want %q", got, want)
		}
	}
	cancel()
	stopped(t, done)
	if s.Stats.Completed.Load() != 4 || s.Stats.Active.Load() != 0 {
		t.Fatal("incorrect session accounting")
	}
}
func TestConnectFailureFallsBack(t *testing.T) {
	dead := listener(t)
	bad := dead.Addr().String()
	dead.Close()
	s, addr, cancel, done := start(t, []string{bad, backend(t, "ok:")}, 8, 200)
	if got := request(t, addr); got != "ok:payload" {
		t.Fatal(got)
	}
	cancel()
	stopped(t, done)
	if s.Stats.DialFailures.Load() != 1 {
		t.Fatal("missing failure counter")
	}
}
func TestAllBackendsDown(t *testing.T) {
	dead := listener(t)
	bad := dead.Addr().String()
	dead.Close()
	s, addr, cancel, done := start(t, []string{bad}, 8, 200)
	c, e := net.Dial("tcp", addr)
	if e != nil {
		t.Fatal(e)
	}
	defer c.Close()
	c.SetDeadline(time.Now().Add(time.Second))
	_, e = c.Read(make([]byte, 1))
	if e == nil {
		t.Fatal("expected closure")
	}
	if ne, ok := e.(net.Error); ok && ne.Timeout() {
		t.Fatal("connection hung")
	}
	cancel()
	stopped(t, done)
	if s.Stats.DialFailures.Load() != 1 {
		t.Fatal("missing failure")
	}
}
func TestConnectionLimitAndForcedDrain(t *testing.T) {
	s, addr, cancel, done := start(t, []string{backend(t, "")}, 1, 30)
	c, e := net.Dial("tcp", addr)
	if e != nil {
		t.Fatal(e)
	}
	defer c.Close()
	eventually(t, func() bool { return s.Stats.Active.Load() == 1 })
	extra, e := net.Dial("tcp", addr)
	if e != nil {
		t.Fatal(e)
	}
	defer extra.Close()
	extra.SetDeadline(time.Now().Add(time.Second))
	_, e = extra.Read(make([]byte, 1))
	if e == nil {
		t.Fatal("expected rejection")
	}
	if ne, ok := e.(net.Error); ok && ne.Timeout() {
		t.Fatal("rejection hung")
	}
	eventually(t, func() bool { return s.Stats.Rejected.Load() == 1 })
	before := time.Now()
	cancel()
	stopped(t, done)
	if time.Since(before) > time.Second || s.Stats.Active.Load() != 0 {
		t.Fatal("drain did not finish")
	}
}
func TestGracefulDrainPreservesResponse(t *testing.T) {
	s, addr, cancel, done := start(t, []string{backend(t, "ok:")}, 2, 1000)
	c, e := net.Dial("tcp", addr)
	if e != nil {
		t.Fatal(e)
	}
	defer c.Close()
	c.SetDeadline(time.Now().Add(2 * time.Second))
	// Ensure the flow was admitted before cancelling.
	io.WriteString(c, "payload")
	eventually(t, func() bool { return s.Stats.Active.Load() == 1 })
	cancel()
	c.(*net.TCPConn).CloseWrite()
	b, e := io.ReadAll(c)
	if e != nil || string(b) != "ok:payload" {
		t.Fatalf("drain lost response %q %v", b, e)
	}
	stopped(t, done)
}
func TestConfigValidation(t *testing.T) {
	valid := `{"version":"l4load.dev/v0alpha1","listen":"127.0.0.1:18080","backends":["127.0.0.1:18081"],"max_connections":2,"connect_timeout_ms":10,"max_session_ms":100,"drain_timeout_ms":10}`
	if _, e := Load(strings.NewReader(valid)); e != nil {
		t.Fatal(e)
	}
	for name, input := range map[string]string{
		"unknown":  strings.Replace(valid, `"max_connections"`, `"typo"`, 1),
		"trailing": valid + ` {}`, "version": strings.Replace(valid, "v0alpha1", "v1", 1),
		"external":         strings.Replace(valid, "127.0.0.1:18080", "0.0.0.0:18080", 1),
		"external_backend": strings.Replace(valid, "127.0.0.1:18081", "192.0.2.1:18081", 1),
		"loop":             strings.Replace(valid, "18081", "18080", 1),
		"zero_limit":       strings.Replace(valid, `"max_connections":2`, `"max_connections":0`, 1),
		"duplicate":        strings.Replace(valid, `["127.0.0.1:18081"]`, `["127.0.0.1:18081","127.0.0.1:18081"]`, 1),
		"empty":            strings.Replace(valid, `["127.0.0.1:18081"]`, `[]`, 1),
	} {
		t.Run(name, func(t *testing.T) {
			if _, e := Load(strings.NewReader(input)); e == nil {
				t.Fatal("accepted invalid config")
			}
		})
	}
}

func TestSessionLifetime(t *testing.T) {
	ln := listener(t)
	s, err := New(Config{"l4load.dev/v0alpha1", ln.Addr().String(), []string{backend(t, "")}, 1, 20, 40, 100})
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() { done <- s.Serve(ctx, ln) }()
	c, err := net.Dial("tcp", ln.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	c.SetReadDeadline(time.Now().Add(time.Second))
	_, err = c.Read(make([]byte, 1))
	if err == nil {
		t.Fatal("expected expired session")
	}
	if ne, ok := err.(net.Error); ok && ne.Timeout() {
		t.Fatal("session lifetime was not enforced")
	}
	cancel()
	stopped(t, done)
	if s.Stats.Active.Load() != 0 {
		t.Fatal("session leaked")
	}
}

func TestOversizedConfiguration(t *testing.T) {
	if _, err := Load(strings.NewReader(strings.Repeat(" ", (1<<20)+1))); err == nil {
		t.Fatal("accepted oversized configuration")
	}
}
