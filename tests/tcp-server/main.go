package main

import (
	"flag"
	"fmt"
	"log"
	"net"
)

func main() {
	port := flag.String("port", "3333", "Port")
	flag.Parse()

	host := GetOutboundIP()
	response := fmt.Sprintf("%v:%v", host, *port)

	l, err := net.Listen("tcp", fmt.Sprintf(":%v", *port))
	if err != nil {
		log.Panicln(err)
	}
	defer l.Close()
	log.Printf("listening to tcp connections at: :%v\n", *port)
	log.Printf("responding with: %v\n", response)

	for {
		conn, err := l.Accept()
		if err != nil {
			log.Panicln(err)
		}

		go handleRequest(conn, response)
	}
}

func handleRequest(conn net.Conn, response string) {
	log.Println("accepted new connection")
	defer conn.Close()
	defer log.Println("closed connection")
	log.Printf("write data to connection: %v\n", response)
	_, err := conn.Write([]byte(response))
	if err != nil {
		log.Printf("error writing to connection: %v", err)
		return
	}
}

// GetOutboundIP https://stackoverflow.com/questions/23558425/how-do-i-get-the-local-ip-address-in-go
func GetOutboundIP() net.IP {
	conn, err := net.Dial("udp", "8.8.8.8:80")
	if err != nil {
		log.Fatal(err)
	}
	defer conn.Close()
	localAddr := conn.LocalAddr().(*net.UDPAddr)
	return localAddr.IP
}
