package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"github.com/l4load/l4load/internal/balance"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"
)

func main() {
	if err := run(); err != nil {
		log.Print(err)
		os.Exit(1)
	}
}
func run() error {
	path := flag.String("config", "examples/local.json", "configuration file")
	check := flag.Bool("check", false, "validate configuration without opening a listener")
	flag.Parse()
	if flag.NArg() != 0 {
		return fmt.Errorf("unexpected positional arguments")
	}
	f, err := os.Open(*path)
	if err != nil {
		return err
	}
	defer f.Close()
	c, err := balance.Load(f)
	if err != nil {
		return err
	}
	if *check {
		fmt.Println("configuration valid (lab-only)")
		return nil
	}
	server, err := balance.New(c)
	if err != nil {
		return err
	}
	ln, err := net.Listen("tcp", c.Listen)
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	log.Printf("Balance lab listening on %s; not production qualified", ln.Addr())
	err = server.Serve(ctx, ln)
	json.NewEncoder(os.Stdout).Encode(map[string]int64{"accepted": server.Stats.Accepted.Load(), "rejected": server.Stats.Rejected.Load(), "dial_failures": server.Stats.DialFailures.Load(), "completed": server.Stats.Completed.Load(), "active": server.Stats.Active.Load()})
	return err
}
