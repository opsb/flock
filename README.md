# Flock

Flock is an Elixir implementation of a leader election algorithm for a cluster of nodes that communicate over plain TCP. It's a small, self-contained exploration of how a fixed set of processes — running in the same VM or on separate machines — can agree on a single leader, notice when the leader disappears, and elect a new one without any external coordination service.

## Why this exists

Distributed systems usually rely on something to break ties: a database, a consensus service like ZooKeeper or etcd, or Erlang's own distribution protocol. Flock deliberately uses none of those. Each node knows only what's in a shared JSON topology file — every peer's name, IP, and port — and the nodes coordinate by exchanging four message types over TCP sockets they open to each other. The goal was to write the algorithm from first principles, in idiomatic Elixir, with the smallest moving parts that still produce correct behaviour when nodes are killed and restarted.

## How it works at a glance

The algorithm is a variant of the bully election. Node IDs are sortable strings, and the highest-ID node that's alive becomes leader. Every node periodically pings the current leader; if the leader stops responding within `4 × T` seconds, the pinger starts an election by sending `ALIVE?` to all peers with a higher ID. Those peers respond `FINETHANKS` and start their own elections; the last node standing announces itself with `IAMTHEKING`. The full state machine — including how a returning higher-ID node reclaims leadership — lives in `lib/flock/node_server.ex`, and the wire format is defined in `lib/flock/protocol.ex`.

## What's in the repo

- `lib/flock/node_server.ex` — the per-node `GenServer` that runs the election state machine.
- `lib/flock/protocol.ex` — encoding/decoding of the four messages (`ALIVE?`, `FINETHANKS`, `PING`, `PONG`, `IAMTHEKING:<id>`).
- `lib/flock/tcp/` — the TCP acceptor, connection, and request-sending plumbing.
- `lib/flock/topology.ex` — parses the JSON topology and answers "who are my peers?" and "who outranks me?".
- `lib/flock/log/` — a small structured event log that the CLI pretty-prints so you can watch state transitions in the terminal.
- `lib/flock/cli.ex` — the `escript` entry point invoked by `./flock`.
- `test/integration_test.exs` — a multi-node integration test that exercises start-up, leader death, and recovery.

Because all nodes can run in a single BEAM VM (each node is just a supervised process tree with its own TCP port), you can reproduce a three-node cluster on `localhost` and watch failover happen in real time using the walkthrough below.

## Build

```
mix run escript.build
```

## Configuration
The cluster is specified in a json file which is passed to the `--topology option`. An example file looks like

```
{
  "node1": {"ip": "127.0.0.1", "port": 44130},
  "node2": {"ip": "127.0.0.1", "port": 44131},
  "node3": {"ip": "127.0.0.1", "port": 44132}
}

```
Each node is given a unique name and has an IP address and port number.

## Running
Start a single node with
```
shell1$ ./flock --nodes node1 --topology example/topology.json
node1> started
```

Start several nodes in the same VM
```
shell1$ ./flock --nodes node1,node2 --topology example/topology.json
node1> started
node2> started
```


## Testing

Run

```
mix test
```

See test/integration_test.exs for a full run through.


## Running through a scenario with 3 nodes

Follow through the following steps to start 3 nodes based on example/topology.json. The nodes are configured to all run on localhost but it's also possible run the nodes at different ip addresses.

#### 1. Start the nodes

Open 3 separate shells and start the nodes up independently

```
shell1$ ./flock --nodes node1 --topology example/topology.json
node1> started
```
```
shell2$ ./flock --nodes node2 --topology example/topology.json
node2> started
```
```
shell3$ ./flock --nodes node3 --topology example/topology.json
node3> started
```

#### 2. Kill the leader

```
shell3$ ctrl-c
```

You should see the following
```
shell1$
node1> following node3
```
```
shell2$
node2> became leader
```

#### 3. Restart the original leader


```
shell3$ ./flock --nodes node3 --topology example/topology.json
node3> started
```
```
shell1$
node1> following node3
```
```
shell2$
node2> following node3
```

## Algorithm

The algorithm used is as follows

### Current Leader Monitoring
Once in T seconds, each node sends a message PING to the Leader. If no response is received in 4xT seconds then the current Leader is considered dead and the node that sent that message begins a new Leader election.

### Leader Election
All nodes know each other (each node knows address and port of any other node). Each node has a unique identifier and identifiers are sortable. There are 3 types of messages: ALIVE? , FINETHANKS , IAMTHEKING .

1. The node that starts the election sends a message ALIVE? to all nodes that have ID greater than ID of the current node.
If nobody responded FINETHANKS in T seconds then the current node becomes the Leader and sends out messages IAMTHEKING .
If the current node received FINETHANKS then it waits for T seconds the message IAMTHEKING and if it's not received then election process is started again.
2. If a node receives ALIVE? then it responds with FINETHANKS message and immediately starts the election.
If the node that received ALIVE? has the biggest ID
then it immediately sends out IAMTHEKING message.
3. If a node receives IAMTHEKING then it remembers the sender of
this message as the Leader.
4. If a node joins the system then it immediately initiates the
election.
