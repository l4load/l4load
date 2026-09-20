package balance

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/netip"
)

type Config struct {
	Version          string   `json:"version"`
	Listen           string   `json:"listen"`
	Backends         []string `json:"backends"`
	MaxConnections   int      `json:"max_connections"`
	ConnectTimeoutMS int      `json:"connect_timeout_ms"`
	MaxSessionMS     int      `json:"max_session_ms"`
	DrainTimeoutMS   int      `json:"drain_timeout_ms"`
}

func Load(r io.Reader) (Config, error) {
	var c Config
	data, err := io.ReadAll(io.LimitReader(r, (1<<20)+1))
	if err != nil {
		return c, err
	}
	if len(data) > 1<<20 {
		return c, fmt.Errorf("configuration exceeds 1 MiB")
	}
	d := json.NewDecoder(bytes.NewReader(data))
	d.DisallowUnknownFields()
	if err := d.Decode(&c); err != nil {
		return c, err
	}
	var extra any
	if err := d.Decode(&extra); err != io.EOF {
		return c, fmt.Errorf("expected exactly one JSON document")
	}
	return c, c.Validate()
}

func (c Config) Validate() error {
	if c.Version != "l4load.dev/v0alpha1" {
		return fmt.Errorf("unsupported version")
	}
	addr, err := netip.ParseAddrPort(c.Listen)
	if err != nil || addr.Port() == 0 || !addr.Addr().IsLoopback() {
		return fmt.Errorf("lab listener must be a numeric loopback address with a nonzero port")
	}
	if len(c.Backends) == 0 || len(c.Backends) > 64 {
		return fmt.Errorf("need 1..64 backends")
	}
	seen := map[netip.AddrPort]bool{}
	for _, b := range c.Backends {
		a, e := netip.ParseAddrPort(b)
		if e != nil || a.Port() == 0 || !a.Addr().IsLoopback() {
			return fmt.Errorf("backend must be a numeric loopback address with a nonzero port: %q", b)
		}
		a = netip.AddrPortFrom(a.Addr().Unmap(), a.Port())
		if a == netip.AddrPortFrom(addr.Addr().Unmap(), addr.Port()) || seen[a] {
			return fmt.Errorf("duplicate backend or direct proxy loop: %q", b)
		}
		seen[a] = true
	}
	if c.MaxConnections < 1 || c.MaxConnections > 10000 {
		return fmt.Errorf("max_connections must be 1..10000")
	}
	if c.ConnectTimeoutMS < 1 || c.ConnectTimeoutMS > 60000 {
		return fmt.Errorf("connect_timeout_ms must be 1..60000")
	}
	if c.MaxSessionMS < 1 || c.MaxSessionMS > 3600000 {
		return fmt.Errorf("max_session_ms must be 1..3600000")
	}
	if c.DrainTimeoutMS < 1 || c.DrainTimeoutMS > 60000 {
		return fmt.Errorf("drain_timeout_ms must be 1..60000")
	}
	return nil
}
