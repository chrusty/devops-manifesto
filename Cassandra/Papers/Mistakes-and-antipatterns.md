Cassandra: Mistakes & anti-patterns
===================================

Introduction
------------
This document is intended to provide some examples of what can go wrong when using Cassandra. Do not try this in your production environments.

Danger-zone
-----------
### The wrong tool for the job
Worth mentioning up front is that Cassandra is not the "perfect database for every occasion". Big problems creep up when people try to cram inappropriate data-models into Cassandra (this usually means "lots of secondary indexes").

### Resource-starvation
Don’t try to run Cassandra on instances that are too small. At a minimum I suggest 4 CPU cores, 16GB RAM, and fast local storage (SSD).

### Table-scans / multi-partition reads
Cassandra’s “linear-scaling” model only applies if you’re not involving every node in the cluster with every query you do.

### Secondary indices
Although they sound convenient on paper, there is no deterministic way to locate the part of the secondary index you’re looking for without involving all nodes in the cluster.

### Running out of disk space
If Cassandra runs out of disk space then it will be very difficult to recover. Performance will degrade because compactions are unable to run, in fact you won’t even be able to scale up the cluster properly. Rule of thumb should be to add storage or nodes when you get to 60%.

### Scaling up / down too quickly
With 3 replicas and local-quorum queries, you can only scale up/down by one node at-a-time without breaking consistency.

### Trying to do too much on one cluster
It is tempting to host several keyspaces for several different applications on one cluster, but this makes performance issues much more difficult to diagnose. It also allows one misbehaving application to adversely impact the rest. Ideally each application would have its own cluster.

### Not having the system clocks synced with NTP
Cassandra uses timestamps to “resolve” conflicts (last write wins). If the clocks are out of sync then this can cause strange behaviour and data loss.

### Not being sympathetic to the storage layer (MASSIVE rows)
Cassandra will attempt to compact rows down until they exist in one SSTable (a process that involves a lot of sequential I/O throughput). In a wide-row schema (one-to-many index patterns) these can grow to be quite large. If these large rows are constantly being modified, this will lead to constant compactions. For this reason you may want to split these large partitions up. This type of problem will not be apparent on day-1 when there is no data.

### Performing unbounded reads (select * from a partition or row)
This seems quite a simple concept, but it is worth remembering to only ask for the columns you need. This is particularly important with wide-row schemas.
