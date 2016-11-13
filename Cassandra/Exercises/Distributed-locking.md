Exercise: Distributed locking
=============================


Overview
--------
In this exercise you will practise a method of achieving distributed locks using Cassandra.


Pre-requisites
--------------
* A working single-node Cassandra cluster (assuming that the container is called "cassandra-1").

### Goals
* Create a schema for distributed-locks and see how to work with them using CQL
* Understand the problem they are trying to solve
* Understand their limitations


### Run "cqlsh" in one of your Cassandra containers

```docker exec -it <container-name/id> cqlsh -C```


Background
----------

Sometimes locks are required in order to protect shared resources, to prevent race-conditions, or to elect leaders. With monolithic applications it is possible to do this using a mutex, but in distributed systems this requires some kind of co-ordination service.

There is a known pattern to do this within Cassandra, effectively a hack on the "IF NOT EXISTS" clause in CQL. Obviously to be of any use (and safety) any locking recipe will need to invole a QUORUM of your nodes, incurring all of the known performance penalties of high consistency levels.

__My advice is to use this recipe with caution, and certainly not at high volumes.__


Steps
-----


### Prepare a simple schema
We’ll use a very simple one-to-one table as an example schema. Schema-definition and data-manipulation is done through the "cqlsh" utility (the command to run this is listed above).


#### Create a keyspace
This CQL statement will create a new keyspace called "examples" using the simple replication-strategy with one replica.

```
CREATE KEYSPACE examples WITH replication = {'class': 'SimpleStrategy', 'replication_factor': '1'};
```

#### Create a "locks" table
This CQL statement will create a new table called "locks" which we will use for our named locks. We will use a default TTL of 15s for this table (a safety-measure in case a client crashes and never releases a lock).
```
CREATE TABLE examples.locks (
  lock_name varchar,
  client_id varchar,
  PRIMARY KEY (lock_name)
) WITH DEFAULT_TIME_TO_LIVE = 15;
```

#### Make a lock called "region-master"
This query will take a lock called "region-master" for a client called "application-server-3" (just so we know who has the lock).
```
INSERT INTO examples.locks (lock_name, client_id) VALUES ('region-master', 'application-server-3') IF NOT EXISTS;
```

#### Attempt to take this lock
This query simulates another client ("application-server-2") attempting to take the "region-master" lock (as long as we do this query within 15 seconds).
```
INSERT INTO examples.locks (lock_name, client_id) VALUES ('region-master', 'application-server-2') IF NOT EXISTS;
```

#### Renew the lock

#### Release the lock


Finishing up
------------
This recipe certainly does work, and is an elegant combination of TTLs and "IF NOT EXISTS". There is a failure scenario in which a client takes a lock, half-completes some job, crashes, then allows the lock to expire. In this scenario there is no way to know how to proceed (or even that it has occurred at all). This is a common problem with auto-expiring ("ephemeral") locks however, and not special to Cassandra. Of course you could model non-ephemeral locks by removing the TTL, but you can imagine the dead-lock scenarios that could occur with that pattern.

Be careful using locks!
