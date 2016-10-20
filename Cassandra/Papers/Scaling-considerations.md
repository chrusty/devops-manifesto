Cassandra: Scaling considerations
=================================


Introduction
------------
This document is intended to provide an introduction to some of the concepts of scaling Cassandra.


How Cassandra scales
--------------------
Scaling is one of the most compelling features of Cassandra, and it has been designed from the ground-up to make this as easy and reliable as possible. You may have heard this described as "__linear scaling__", which means "___twice the nodes, twice the power... 4 times the nodes, 4 times the power... 10 times the nodes, 10 times the power___" (though I would add the caveat "as long as you don't do table-scans or use secondary indices").

Effectively there are 2**64 (18446744073709551615) possible partition-keys in a Cassandra table. If you have one node then that node has to hold all of that data, and participate in 100% of the queries. If you have two, then that workload is halved (of course in practise this is slighly complicated by having multiple copies of each partition, and involving several of these in your queries using stronger consistency levels).

This is the fundamental principal behind Cassandra's ability to scale.


Scaling in general
------------------
### Things to be careful of
There are a few things that can cause issues during scaling exercises. Take your time to plan properly, and particularly watch out for the following scenarios.

#### Scaling too quickly
When working with Cassandra clusters you should always be aware of your failure tolerance. This applies to scaling operations too - because a new node will not be able to serve queries until it has finished joining / streaming data, it should be considered as a "failed" node until it has all of the data required to participate in serving queries.

For this reason, ___if you only have 3 replicas and are using QUORUM queries, you can only ever introduce one new node at a time without causing a data outage.___ Of course, larger numbers of replicas allow more nodes to be worked on at the same time.


#### Scaling too late
Due to the fact that you need to add/remove nodes slowly and that it can take a long time for new nodes to join/leave, it can take a long time to scale clusters up or down.

For this reason, unless you have either a tiny amount of data or extremely fast network and storage, ___it is better to scale pro-actively (ahead of time) than reactively___ (when you already need the extra capacity).


Things that don't scale well
----------------------------
### Shared / network-attached storage
Shared-storage / NAS / SAN configurations are not advisable, because their storage and I/O capacity are fundamentally finite. One of the reasons Cassandra is able to offer "linear scaling" characteristics is because each new node added to the cluster brings its CPU, RAM and storage I/O with it.

If this I/O is coming from shared storage then the effect of adding new nodes could actually REDUCE the overall performance of the cluster by contending for finite resources, whereas locally-attached storage is never in contention.


### Table scans
Cassandra's scaling model is based on the idea of sharding the responsibility for servicing queries between more machines. Scanning tables works completely against this concept - this type of query MUST involve every token-range in the entire cluster, and adding more nodes will in fact only make the performance worse.

This is why I say that ```SELECT * FROM <table>;``` should be considered "_illegal_". 


### Secondary indices
Arbitrary indexing is the thorn in Cassandra's side (in terms of data-modelling). While using partitions and clustering-columns allows some powerful modelling scenarios, it can never allow the type of indexing available in traditional databases.

Cassandra DOES allow "[secondary indexes](https://docs.datastax.com/en/cql/3.0/cql/cql_reference/create_index_r.html)", and to the uninitiated this can appear to be the answer to all data-modelling issues, but I would question whether they should ever be used at all.

The problem with secondary indexes in Cassandra comes down to the way that they are distributed around the cluster. ___Instead of being distributed by the indexed column value, secondary indexes are distributed by the partition-key of the row containing the indexed value___. This means that there is no way to determine which nodes in your cluster are responsble for your indexed value, therefore every node will be involved in fulfilling your queries! In practise this is the same problem as performing table scans - adding more nodes to your cluster will not help your index perform any better, in fact it will be worse. Of course there are good justifications for this behaviour: it avoids having "hot" partitions or nodes, and it also allows more than simple "equality / =" WHERE clauses in your queries.

More is written about this [here](https://pantheon.io/blog/cassandra-scale-problem-secondary-indexes).
Even [DataStax themselves warn you about secondary indices](https://docs.datastax.com/en/cql/3.1/cql/ddl/ddl_when_use_index_c.html#concept_ds_sgh_yzz_zj__highCardCol)

#### So what are the alternatives to using secondary indexes?
* If you can't model around the problem, then de-normalise your data and maintain tables for your indexes (either by performing multiple inserts, or using materialised-views to maintain them for you). This decision should not be taken lightly however, as it will incur very real performance and storage overheads. It also turns your single-partition writes into multi-partition writes involving several nodes of the cluster (and incurring the associated compaction overheads).
* I often advise people that "___if you can't model your data for Cassandra without requiring large numbers of secondary indexes, then you are probably using the wrong tool for the job___". Why not run something like ElasticSearch alongside Cassandra? I would personally like to see a way to offload secondary indexes to external systems in the future.


Scaling for performance
-----------------------
If you are looking to improve your baseline performance (response times), then you should probably look at vertically scaling your storage bandwidth or improving your data models. If however you are looking to reduce the extreme examples of query latency then adding nodes to the cluster could be the way to go.

One common mistake I have encountered is when people take "commodity hardware" to mean "Raspberry Pi". There is no point running your Cassandra cluster on tiny instances and horizontally scaling them out. You need to be a bit more realistic with the type of instances you choose to host Cassandra on in the first place.

Having powerful instances will help you maintain a good average response time even when background tasks such as repairs / compactions / backups / streaming are taking place.

### Here are some guidelines
* __CPU__: 4 cores, 8 if you can (this helps with background tasks, and can improve garbage-collection times)
* __RAM__: 8GB minimum, 16 is better, even more is better still. Don't give this to the JVM though - Linux is good at caching frequently-accessed files for you.
* __Disk__: Locally-attached SSDs are good, and if you have more than 1 replica of your datasets then these don't need to be configured for resilience (a raid-0 / stripe-set is fine, and improves bandwidth even more). Disk I/O is the single best thing you can give Cassandra.

### A good benchmark instance type for hosting Cassandra on EC2 is the c3.xlarge
* __CPU__: 8 cores
* __RAM__: 15GB
* __DISK__: 2 x 80GB "ephemeral" (locally-attached) SSD volumes which can be striped together
* __I/O allocation__: HIGH (whatever that means)

With decent data-models I can reliably achieve u95 read-latencies of ~2.5ms on these instances.

### A note on data-density
While powering up your nodes is one way to help background tasks get dealt with quickly, another effective way is to store less data on each node.


Scaling for storage capacity
----------------------------
In the same way that adding more nodes to a cluster allows it to serve more queries, adding more nodes also allows it to store more data (as long as your replication strategy isn't trying to store 100% of your data on every node).

### Which direction to scale
While tempting to store as much data on each node as possible, this also means that each node will end up having to serve more queries than if you'd allowed lower storage densities. It also means that tasks like repairs / backups / joining / leaving will take much longer to complete. It also exposes you to nasty failure scenarios if you happen to have a second node go offline while one is taking hours to rebuild because you chose to store 2TB on each one.

My recommendation is to ___NEVER vertically scale for storage capacity___, and to add more nodes instead.

### When to scale out
I generally advise people that ___the time to start adding more storage is when your data filesystems approach 60%___ of their total capacity. This is because compactions can temporarily require large amounts of free storage space, and streaming data to a new node joining the cluster will probably require some compactions to be performed on the old nodes.


Scaling for geographic distribution
-----------------------------------
Scaling your cluster geographically involves building entirely new clusters in remote locations, then joining them to the rest of your nodes.

### Procedure
* Build a new cluster in a new datacentre somewhere.
* Make sure that your entire cluster is configured with the same "cluster_name" setting.
* Every node needs to be using a "snitch" that supports rack & data-centre awareness (each node needs to know which rack & DC it belongs to, one way or another).
* You of course need to provision some kind of WAN connection, perhaps a VPN.
* Now just point some of the nodes at each other across the VPN (using seed addresses), bring them up, and you will have a multi-DC cluster.
* You will now need to make sure that your schemas are using the "NetworkTopologyStrategy" (NTS), and are configured to include replicas at both the old DCs and the new one you've just brought online.
* At this time you can use the ```nodetool rebuild <olddc>``` command on your new nodes (one at a time if you're worried about the impact), and they will stream data from the existing nodes across the WAN link.

### Scaling concerns
The procedure should work fine and is quite safe to do, but there will be very real implications for your WAN connection. Be realistic about the amount of data you expect to be transferred over this connection, and certainly graph it. ___If simply rebuilding nodes across the WAN can't keep up with the live rate of changed data then I would question how you expect to cope with real live problems further down the track___.

Also worth noting: before you bring new datacentres online make sure that nobody is using ALL or QUORUM queries, because they will suddenly involve nodes from across the WAN link (slowing them down and inviting availability exposure).