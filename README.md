# Flock

Implementation of a clustering algorithm using TCP as a transport.

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
