// Copyright 2015 The Gorilla WebSocket Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"sync"

	"github.com/gorilla/websocket"
)

/* json */

type command struct {
	Cmd string
	Val int
}

/* pub/sub */

type hubPubSub struct {
	mu     sync.RWMutex
	subs   map[string]map[string]chan string
	closed bool
}

func newhubPubSub() *hubPubSub {
	ps := &hubPubSub{}
	ps.subs = make(map[string]map[string]chan string)
	return ps
}

func (ps *hubPubSub) subscribe(id string, topic string) (ch chan string) {
	ps.mu.Lock()
	defer ps.mu.Unlock()

	if _, ok := ps.subs[topic]; !ok {
		ps.subs[topic] = make(map[string]chan string)
	}

	ch = make(chan string, 1)
	ps.subs[topic][id] = ch

	return
}

func (ps *hubPubSub) unsubscribe(id string, topic string) {
	ps.mu.Lock()
	defer ps.mu.Unlock()

	if _, ok := ps.subs[topic]; ok {
		if !ps.closed {
			close(ps.subs[topic][id])
		}
		delete(ps.subs[topic], id)
	}
}

func (ps *hubPubSub) publish(topic string, msg string) {
	ps.mu.RLock()
	defer ps.mu.RUnlock()

	if ps.closed {
		return
	}

	if _, ok := ps.subs[topic]; ok {
		for id := range ps.subs[topic] {
			ps.subs[topic][id] <- msg
		}
	}
}

func (ps *hubPubSub) close() {
	ps.mu.Lock()
	defer ps.mu.Unlock()

	if !ps.closed {
		ps.closed = true
		for topic := range ps.subs {
			for id := range ps.subs[topic] {
				close(ps.subs[topic][id])
			}
		}
	}
}

/* websocket */

var addr = flag.String("addr", ":8080", "http service address")

var upgrader = websocket.Upgrader{}
var hub *hubPubSub

func main() {
	hub = newhubPubSub()
	go handleCli()

	flag.Parse()
	log.SetFlags(0)
	http.HandleFunc("/control", control)
	http.HandleFunc("/", home)
	log.Fatal(http.ListenAndServe(*addr, nil))
}

func home(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintf(w, "websocket test")
}

func control(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Print("upgrade:", err)
		return
	}

	defer conn.Close()

	id := conn.RemoteAddr().String()
	cli := hub.subscribe(id, "user")
	defer hub.unsubscribe(id, "user")
	fmt.Printf("new subscriber: %s\n", id)

	net := make(chan string)
	go handleNet(net, conn)

	for {
		select {
		case message, more := <-cli:
			if more == false {
				return
			}

			err := conn.WriteMessage(websocket.TextMessage, []byte(message))
			if err != nil {
				fmt.Printf("failed to write to client %s: %s\n", id, err)
				return
			}

		case message, more := <-net:
			if more == false {
				fmt.Printf("client %s disconnected\n", id)
				return
			}

			fmt.Printf("recv: %s\n", message)
		}
	}
}

func handleNet(cc chan string, conn *websocket.Conn) {
	for {
		_, message, err := conn.ReadMessage()
		if err != nil {
			fmt.Printf("failed to read from client %s: %s\n", conn.RemoteAddr(), err)
			close(cc)
			return
		}

		cc <- string(message)
	}
}

func handleCli() {
	reader := bufio.NewReader(os.Stdin)

	for {
		var cmd command

		fmt.Print("Enter message: ")
		str, err := reader.ReadString('\n')
		if err != nil {
			if err != io.EOF {
				fmt.Printf("err: stdio read: %s\n", err)
			}

			hub.close()
			break
		}

		_, err = fmt.Sscanf(str, "%s %d\n", &cmd.Cmd, &cmd.Val)
		if err != nil {
			_, err = fmt.Sscanf(str, "%s\n", &cmd.Cmd)
			if err != nil {
				fmt.Printf("err: scanf: %s\n", err)
				fmt.Printf("format: <command> <value>\n")
				continue
			}
		}

		dat, err := json.Marshal(cmd)
		if err != nil {
			fmt.Printf("err: json marshaling: %s\n", err)
			continue
		}

		hub.publish("user", string(dat))
	}

	os.Exit(0)
}
