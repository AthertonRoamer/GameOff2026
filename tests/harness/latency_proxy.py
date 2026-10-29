"""Local UDP proxy that adds latency, jitter and packet loss between one ENet client and a server.

    py -3 latency_proxy.py --listen 5100 --target 5000 --delay-ms 100 --jitter-ms 10 --loss 2

The client connects to 127.0.0.1:<listen>, the proxy forwards to 127.0.0.1:<target>. The delay is applied in each
direction, so the round trip grows by twice --delay-ms. Only one client is supported.
"""
import argparse
import heapq
import random
import socket
import sys
import threading
import time


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--listen", type=int, required=True)
    parser.add_argument("--target", type=int, required=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--delay-ms", type=float, default=0.0, help="one-way delay")
    parser.add_argument("--jitter-ms", type=float, default=0.0, help="random extra one-way delay, 0 to this value")
    parser.add_argument("--loss", type=float, default=0.0, help="packet loss in percent, each direction")
    args = parser.parse_args()

    front = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    front.bind((args.host, args.listen))
    back = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    back.bind((args.host, 0))
    server_addr = (args.host, args.target)

    state = {"client": None}
    queue: list = []
    cond = threading.Condition()
    counter = [0]

    def schedule(sock: socket.socket, data: bytes, addr) -> None:
        if random.random() * 100.0 < args.loss:
            return
        delay = (args.delay_ms + random.random() * args.jitter_ms) / 1000.0
        with cond:
            counter[0] += 1
            heapq.heappush(queue, (time.monotonic() + delay, counter[0], sock, data, addr))
            cond.notify()

    def sender() -> None:
        while True:
            with cond:
                while not queue or queue[0][0] > time.monotonic():
                    wait = None if not queue else max(0.0, queue[0][0] - time.monotonic())
                    cond.wait(wait)
                _, _, sock, data, addr = heapq.heappop(queue)
            try:
                sock.sendto(data, addr)
            except OSError:
                pass

    def from_client() -> None:
        while True:
            try:
                data, addr = front.recvfrom(65535)
            except ConnectionResetError:
                continue
            state["client"] = addr
            schedule(back, data, server_addr)

    def from_server() -> None:
        while True:
            try:
                data, _ = back.recvfrom(65535)
            except ConnectionResetError:
                continue
            if state["client"] is not None:
                schedule(front, data, state["client"])

    for target in (sender, from_client, from_server):
        threading.Thread(target=target, daemon=True).start()
    print(f"proxy 127.0.0.1:{args.listen} -> {args.target}, +{args.delay_ms}ms each way, jitter {args.jitter_ms}ms, loss {args.loss}%", flush=True)
    try:
        while True:
            time.sleep(1.0)
    except KeyboardInterrupt:
        sys.exit(0)


if __name__ == "__main__":
    main()
