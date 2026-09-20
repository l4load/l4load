package balance

import (
	"context"
	"errors"
	"io"
	"net"
	"sync"
	"sync/atomic"
	"time"
)

type Stats struct{ Accepted, Rejected, DialFailures, Completed, Active atomic.Int64 }

type Server struct {
	config Config
	next   atomic.Uint64
	Stats  Stats
}

func New(c Config) (*Server, error) {
	if err := c.Validate(); err != nil {
		return nil, err
	}
	c.Backends = append([]string(nil), c.Backends...)
	return &Server{config: c}, nil
}

// Serve owns the listener and drains sessions before forcing closure.
func (s *Server) Serve(ctx context.Context, ln net.Listener) error {
	defer ln.Close()
	flowCtx, cancelFlows := context.WithCancel(context.Background())
	defer cancelFlows()
	stop := context.AfterFunc(ctx, func() { ln.Close() })
	defer stop()
	var wg sync.WaitGroup
	slots := make(chan struct{}, s.config.MaxConnections)
	var serveErr error
	for {
		conn, err := ln.Accept()
		if err != nil {
			if ctx.Err() == nil {
				serveErr = err
			}
			break
		}
		if ctx.Err() != nil {
			conn.Close()
			break
		}
		s.Stats.Accepted.Add(1)
		select {
		case slots <- struct{}{}:
			s.Stats.Active.Add(1)
			wg.Add(1)
			go func() {
				defer wg.Done()
				defer func() { <-slots; s.Stats.Active.Add(-1); s.Stats.Completed.Add(1) }()
				s.proxy(flowCtx, conn)
			}()
		default:
			s.Stats.Rejected.Add(1)
			conn.Close()
		}
	}
	done := make(chan struct{})
	go func() { wg.Wait(); close(done) }()
	timer := time.NewTimer(time.Duration(s.config.DrainTimeoutMS) * time.Millisecond)
	defer timer.Stop()
	select {
	case <-done:
	case <-timer.C:
		cancelFlows()
		<-done
	}
	return serveErr
}

func (s *Server) proxy(ctx context.Context, client net.Conn) {
	defer client.Close()
	deadline := time.Now().Add(time.Duration(s.config.MaxSessionMS) * time.Millisecond)
	ctx, cancel := context.WithDeadline(ctx, deadline)
	defer cancel()
	stopClient := context.AfterFunc(ctx, func() { client.Close() })
	defer stopClient()
	client.SetDeadline(deadline)
	// Share one dial budget; never replay application bytes.
	dialCtx, cancelDial := context.WithTimeout(ctx, time.Duration(s.config.ConnectTimeoutMS)*time.Millisecond)
	defer cancelDial()
	start := (s.next.Add(1) - 1) % uint64(len(s.config.Backends))
	var upstream net.Conn
	for i := 0; i < len(s.config.Backends); i++ {
		var err error
		upstream, err = (&net.Dialer{}).DialContext(dialCtx, "tcp", s.config.Backends[(int(start)+i)%len(s.config.Backends)])
		if err == nil {
			break
		}
		s.Stats.DialFailures.Add(1)
		if dialCtx.Err() != nil {
			return
		}
	}
	if upstream == nil {
		return
	}
	defer upstream.Close()
	stopUpstream := context.AfterFunc(ctx, func() { upstream.Close() })
	defer stopUpstream()
	upstream.SetDeadline(deadline)
	done := make(chan struct{})
	copyHalf := func(dst, src net.Conn) {
		_, err := io.Copy(dst, src)
		if err != nil && !errors.Is(err, net.ErrClosed) {
			client.Close()
			upstream.Close()
			return
		}
		// A client may finish writing and still wait for the backend response.
		if tcp, ok := dst.(*net.TCPConn); ok {
			tcp.CloseWrite()
		} else {
			dst.Close()
		}
	}
	go func() { copyHalf(upstream, client); close(done) }()
	copyHalf(client, upstream)
	<-done
}
