Cassandra: Cheat-sheet
======================


Introduction
------------
This document is intended to provide a quick reference to some common Cassandra terminology, and some helpful commands.


Terminology & Concepts
----------------------

### KeySpace
A KeySpace is a named collection of tables (analogous to a "schema" or "database" in MySQL). Certain defaults are configured on a per-keyspace basic (such as replication settings). KeySpaces are also useful logical security zones when specifying ACLs.

### Table / ColumnFamily
A table (previously known as a "ColumnFamily" should be thought of in much the same way as a table in a traditional database. Really it is a definition of an index for a set of similar data-objects with a defined schema.

### Partition
A "partition" is a chunk of data addressable in a Cassandra cluster (a key/value pair).
* This can appear to be many rows and columns
* A partition is entirely stored on one node (never spills over)
* Rows within a partition can be ordered and sliced
* Data can be modelled using a partition as a mini table

### Row
A "row" is an entry within a partition. It can be thought of as a row in a traditional database. Historically a "partition" was called a "row", and you will still see references to this in some of the documentation. This is confusing, sorry.


### Wide-row
The term "wide-row" is used to describe a data-model which allows rows to grow horizontally. In practise this means that a partition can have an arbitrarily large number of rows.

### Compaction
New files appear on disk whenever data is written to Cassandra. To avoid having to read all of these files each time data is queried, Cassandra tries to maintain a smaller number of more-dense files on disk. This process is known as "compaction".

[Compaction](http://docs.datastax.com/en/cassandra/2.0/cassandra/dml/dml_write_path_c.html#concept_ds_wt3_32w_zj__dml-compaction "DataStax")


### Replication-factor / strategy
Cassandra KeySpaces can be configured to replicate data in different ways. This can be quite simple, or involve an amount of locational awareness.
* "__SimpleStrategy__" just treats every node in the cluster the same, and attempts to evenly distribute data between them (whilst ensuring that the specified number of replicas is maintained for each partition).
* "__NetworkTopologyStrategy__" allows you configure multiple-datacentre topologies, and ensure that the desired number of replicas is maintained in each. Cassandra will also attempt to maintain the replicas in as many different logical "racks" as possible.

[Data replication](http://docs.datastax.com/en/cassandra/2.0/cassandra/architecture/architectureDataDistributeReplication_c.html "DataStax")


### Tunable-consistency
Cassandra allows the user to choose the appropriate consistency-level for each query. Strong consistency queries involve more cluster members, take more time, and will fail if those cluster members are unavailable. Low consistency queries are of course faster, involve fewer nodes, and will allow you to get responses even when nodes are unavailable (according to your replication-strategy).

Most people who care about the data they’re storing end up using a combination of replication-factor 3, and quorum queries. This allows queries to return even when a node is down, but also guarantees data consistency.

[Configuring data consistency](http://docs.datastax.com/en/cassandra/2.0/cassandra/dml/dml_config_consistency_c.html?hl=consistency "DataStax")


### Repair
Opportunities for your data to become "inconsistent" arise during the course of day-to-day operations unless you’re using the absolute highest consistency options (and suffering the associated performance and availability issues arising from this). A well-designed application and cluster topology should be able to cope with these scenarios, but Cassandra has the ability to repair its data consistency to match your desired replication settings.

A repair is coordinated by one node in the cluster against a certain range of the overall data (or all of it). This effectively asks all of the nodes responsible for this data to analyse what they have on disk and produce checksums for it, then report back to the coordinator node. The coordinator node then compares the results, and asks for any differences to be reconciled.

Regular repairs should be scheduled on every cluster (usually once per week).

[Repairing nodes](http://docs.datastax.com/en/cassandra/2.0/cassandra/operations/ops_repair_nodes_c.html?hl=repair "DataStax")


### Gossip
Cassandra clusters use a "gossip" protocol to share status information for things like:
* Membership (new nodes joining)
* Node status (up/down)
* Load (how much data each node has)

[Internode communications](http://docs.datastax.com/en/cassandra/2.0/cassandra/architecture/architectureGossipAbout_c.html?hl=gossip "DataStax")


### Hinted Handoff
Cassandra nodes can accept data even if it is not specifically for themselves. In this case a node will figure out which of its peers is responsible for the data and attempt to forward it on. If the node they’re trying to talk to is down, then the data will be locally cached and forwarded later on when the node they want is back up. This process is known as "hinted handoff".

[About hinted handoff writes](http://docs.datastax.com/en/cassandra/2.0/cassandra/dml/dml_about_hh_c.html "DataStax")


### SSTable
* Cassandra’s on-disk data-format (Sorted Strings Table).
* New data is flushed periodically to disk as SSTables.
* SSTables are IMMUTABLE (can’t be changed, only deleted).
* Data is ordered (this allows rows in a partition to be ordered).

[Cassandra SSTable Storage Format](http://distributeddatastore.blogspot.co.uk/2013/08/cassandra-sstable-storage-format.html "distributeddatastore")


Useful Commands
---------------
This section includes a list of some of the most useful commands you may need to work with Cassandra. Most of these are subcommands of the "nodetool" utility which comes with Cassandra. Nodetool is really just a JMX client - all of these endpoints are available through Cassandra’s JMX interface.

### Status
The following commands can be used to find the current status of various aspects of your cluster and nodes.

#### Cluster membership
The ```nodetool status``` command shows the UP/DOWN status of every node in the cluster, including data volumes. This can be run from any active node in the cluster.

#### Current node status
The ```nodetool info``` command returns detailed status information about the node you’re currently connected to. Information includes:
* Service status
* Data volume
* Memory usage
* Logical location info (rack/DC)
* Exception count
* Cache efficiency

#### Current node version
The ```nodetool version``` command returns the version of Cassandra currently installed.

#### Cluster versions (according to Gossip)
The ```nodetool gossipinfo``` command returns the versions of Cassandra reported by all of the cluster nodes, as well as some other useful info like locations and schema versions. Useful when performing a rolling-upgrade across a cluster.


### Operations
The following commands will be useful when performing common operational tasks.

#### Dump the entire schema to a file
You can use CQLSH to dump all of the schema definitions to a file:
```echo 'DESCRIBE FULL SCHEMA;' |cqlsh >schema.cql```

#### Repair
You will sometimes need to trigger a repair on some of your data. 
* ```nodetool repair``` will repair all of the data in your cluster
* ```nodetool repair keyspace1``` will repair only the "keyspace1" keyspace
* ```nodetool repair keyspace1 table1``` will repair only the "table1" table in that keyspace

Repairs can take time, so it’s best to run these in screen / tmux

#### Assassinate the ghost of a dead node
If you ever have to replace one of the nodes in your cluster with a new one, you will find that the ```nodetool status``` command still shows the old node in the list as being "down". The cluster of course can’t know that the old one isn’t coming back, so you need manually remove it using the "assassinate" command (___DANGER ZONE___).
* ```nodetool assassinate 10.1.2.3``` will remove any memory of 10.1.2.3 (you should run a repair after doing this).


### Performance and monitoring
The following commands can be very useful when diagnosing performance-related issues (though you’ll need to have some idea which keyspace and table you’re looking for).

### System-wide threadpool status
The ```nodetool tpstats``` command shows you some basic stats on some of Cassandra’s internal thread-pools. The only real use for this is to make observations along the lines of _"I can see that a bunch of stuff has been blocked, therefore this node is starved of resources (probably I/O)"_.

### Per-table statistics
The ```nodetool cfstats``` (or ```nodetool tablestats``` in more recent versions) command gives you performance statistics for every table in every keyspace. Particularly useful stats are:
* Average read-latency (high values indicate poor data-access patterns / models)
* Average write-latency (high values would be very rare and suggest very serious resource constraints)
* Partition min/avg/max sizes (useful to see if you have any strangely outlying partition abuse)
* Read & write operation count (know how many queries are being performed)

### Single-table statistics
This is the most powerful command-line tool for diagnosing performance issues. To be in this position you already know which table is giving you trouble, and you’re trying to figure out why.

The command ```nodetool tablehistograms keyspace1 standard1``` (previously "cfhistograms") gives me a table of stats for the table called "standard1" in the "keyspace1" keyspace (this was created by the stress-test util).
```
root@ee2b5561ca20:/# nodetool tablehistograms keyspace1 standard1
keyspace1/standard1 histograms
Percentile  SSTables     Write Latency      Read Latency    Partition Size        Cell Count
                              (micros)          (micros)           (bytes)
50%             0.00             24.60              0.00               258                 5
75%             0.00             29.52              0.00               258                 5
95%             0.00             61.21              0.00               258                 5
98%             0.00            105.78              0.00               258                 5
99%             0.00            152.32              0.00               258                 5
Min             0.00              8.24              0.00               216                 5
Max             0.00         155469.30              0.00               258                 5
```

This output tells me the distribution of read and write query latencies, the distribution of the partition-sizes (and number of "rows" in each), and the number of files that had to be hit on disk to service the read-queries.