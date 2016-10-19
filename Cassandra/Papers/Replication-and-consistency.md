Cassandra: Replication & consistency
====================================


Introduction
------------
This document is intended to provide an explanation of how replication works together with Cassandra’s consistency-levels, allowing you to select the right balance between consistency, performance and availability.

As the concepts discussed relate directly to CAP Theorem, that is a natural place to start.


CAP Theorem
-----------
CAP Theorem is a concise way of defining the problems that people hosting a distributed database (like Cassandra) have to navigate. Without an appreciation for this it will be very difficult to provide/support suitable data solutions based on Cassandra.

### In general (from WikiPedia)
>> [CAP Theorem](https://en.wikipedia.org/wiki/CAP_theorem) (also named Brewer's theorem after computer scientist Eric Brewer) states that it is impossible for a distributed computer system to simultaneously provide all three of the following guarantees:
>> * [Consistency](https://en.wikipedia.org/wiki/Consistency_(database_systems)) (every read receives the most recent write or an error)
>> * [Availability](https://en.wikipedia.org/wiki/Availability) (every request receives a response, without guarantee that it contains the most recent version of the information)
>> * [Partition tolerance](https://en.wikipedia.org/wiki/Network_partitioning) (the system continues to operate despite arbitrary partitioning due to network failures)
>> In other words, the CAP theorem states that in the presence of a network partition, one has to choose between consistency and availability.

### Applied to Cassandra
Fortunately for us, Cassandra provides ways to work with combinations of these CAP requirements by working with consistency-levels and replication-strategies.

### Replication-strategies
Cassandra [allows users to define how many copies of their data will be stored in the cluster](https://docs.datastax.com/en/cassandra/2.0/cassandra/architecture/architectureDataDistributeReplication_c.html), and where they will be placed (using "rack" and "data-centre" aware topologies such as "NetworkTopologyStrategy"). Having more than one copy of the data is what allows Cassandra to be highly-available. Having more than one copy of the data also invites inconsistency under certain circumstances.

### Consistency-level
Cassandra [allows users to select the consistency requirements](http://docs.datastax.com/en/cassandra/2.0/cassandra/dml/dml_config_consistency_c.html) each time they perform a query. This essentially tells Cassandra how many of the replicas of the queries data are involved to perform the query.


Coping with failure
-------------------
Despite how virtualised we consider our environments to be and however expensive the equipment hosting it is, failure should not be considered as the exception to the rule - any well designed system should be able to keep running even when some of the individual components break (according to your appetite for outages). This becomes particularly important in a dynamic environment such as AWS, where no guarantees on the lifetime of an individual instance are made.

Cassandra gives us two ways to deal with this: replication / redundancy, and tunable-consistency. We can choose to have so many copies of everything that it doesn’t matter if some break, or we can choose to make a trade-off in terms of consistency and give out perhaps slightly out-of-date information in times of trouble.

### Redundancy
Although this is a tempting label for unreliable computers, in this case I am using this term to refer to parts of a system for which failure can be anticipated and worked with / mitigated against.

| Failure Unit           | Mitigation                                   |
| ---------------------- | -------------------------------------------- |
| A disk drive           | Use RAID or mirroring                        |
| A Cassandra "node"     | Have multiple replicas on different nodes    |
| A rack full of nodes   | Have enough racks per DC to use LOCAL_QUORUM |
| A data-centre of racks | Have enough DCs to use QUORUM                |

### Consistency
The full-redundancy route carries a considerable amount of overhead when we start considering hosting 3 data-centres each with at least 3 nodes in them. The alternative is to give up on consistency a little bit.

If your application can handle it then you could at first attempt strong-consistency (global) queries, and if they were to fail then fall-back to lower consistency (local) levels.


Applying Cassandra to CAP Requirements
--------------------------------------
The following sections explain how to achieve useful combinations within the CAP Theorem requirements of Consistency, Availability, and Partition-tolerance.


### Consistency & Availability (CA)
The requirement for both consistency and availability can be achieved by having enough copies of the data to allow queries to work against the majority of them at any one time. This is known as "_quorum_" or "_consensus_". If more than half of the replicas are involved, then it is impossible to get the incorrect result. The penalty for involving multiple replicas however is that queries will of course require more resources and will take more time to complete.

#### Single DC
In a single data-centre Cassandra cluster it is possible to have both strong consistency AND high availability by making use of the __QUORUM__ consistency level. Quorum queries require more than half of the replicas to respond.

| Replicas | Quorum | Acceptable Failed Replicas | C/A Tolerant? |
| -------- | ------ | -------------------------- | ------------- |
| 1        | 1      | 0                          | no            |
| 2        | 2      | 0                          | no            |
| 3        | 2      | 1                          | yes           |
| 4        | 3      | 1                          | yes           |
| 5        | 3      | 2                          | yes           |
| 6        | 4      | 2                          | yes           |

This table indicates that the minimum number of replicas required to provide a C/A combination is 3 (which allows queries to be served even when one of the replicas is offline). Choosing 4 replicas still only allows 1 replica to be offline, so 5 is the minimum replication-factor which allows more than 1 replica to be offline while still guaranteeing consistency. Of course, maintaining 5 replicas is quite an overhead in terms of performance and cost. This is why most people running small-scale clusters choose to use 3 replicas.

#### Multi DC
In a multi data-centre Cassandra cluster it is also possible to achieve a CA combination, but this requires EVERY query to involve remote replicas. This approach should not be taken lightly, as it means that every query will be at least as slow as the WAN-link round-trip. Remember that in this scenario there are more points of failure: previously it was just the number of nodes, but now we have entire data-centres which can go offline (and given the nature of WAN links this should be considered the rule rather than the exception).

| Replicas per DC | DCs | Quorum | DCs Involved | C/A Tolerant? |
| --------------- | --- | ------ | ------------ | ------------- |
| 1               | 2   | 2      | 2/2          | no            |
| 2               | 2   | 3      | 2/2          | no            |
| 3               | 2   | 4      | 2/2          | no            |
| 1               | 3   | 2      | 2/3          | yes           |
| 2               | 3   | 4      | 2/4          | yes           |
| 3               | 3   | 5      | 2/5          | yes           |
	

This table indicates that the minimum number of data-centres required to achieve a multi-DC CA combination is 3. While this IS possible with only one replica at each DC, this is really only a theoretical minimum. In practise most people would choose to have at least 3 replicas per data-centre, because this provides solutions for other types of CAP combinations (mentioned later in this document).

#### The bottom line
__To achieve CA you need to use QUORUM queries and have a minimum of 3 replicas.__


### Consistency & Partition-tolerance (CP)
The requirement for both consistency and partition-tolerance can not be achieved for an entire cluster, ever. This would effectively be stating that all nodes of the cluster should be able to respond with the correct results even if some of them are unable to communicate with the rest. Until we have quantum teleportation this will always be a problem, so until that point we need to design our systems a little differently.
Single DC
In a single DC you can overcome network partitioning by applying retries and timeouts to the CA approach outlined above. Simply put, if a QUORUM query happens to land in a part of the network which doesn’t have enough nodes to serve it then it will fail. In this situation the application simply needs to retry on another node.


For this reason I strongly recommend hosting Cassandra clusters in 3 racks per DC. Rack-aware Cassandra will distributed replicas between as many racks as possible, as racks are considered to be another unit of failure.
Multi DC
In a multi DC cluster the same rules apply, although a client configured to only talk to "DC-local" Cassandra instances will not be able to execute QUORUM queries if all other DCs are unavailable.
The bottom line
Short of diverting traffic to healthy datacentres, there is not much else that can be done for "cut-off" partitioned sections of a Cassandra cluster if consistency is important.


There is still a way to guarantee availability however, and this is the subject of the third and final CAP combination.
________________
Availability & Partition-tolerance (AP)
In light of the shortcomings of the CP approach, AP requirements are a little easier to work with. We have so far only dealt with STRONG consensus-based consistency models, where the focus was on the "C". While Cassandra can handle those modes, taking consistency out of the requirement (or at least reducing it somewhat) makes the job even easier.


You have probably heard Cassandra being described as "eventually consistent" (this is what happens if you don’t make use of the stronger consistency-levels). The following scenarios rely on this eventual consistency to asynchronously replicate the data between the partition-prone segments, while still allowing optionally high consistency levels within local areas or "failure units".
Single DC
For a single DC cluster to retain AP characteristics, the only consistency-level you could use would be "ONE". This means that only one replica needs to respond before a query can successfully return. It is still of course good practise to have more than one replica.


Replicas
	Acceptable Failed Replicas
	AP Tolerant?
	1
	0
	no
	2
	1
	yes
	3
	2
	yes
	

This table indicates that it is possible to achieve AP tolerance with only 2 replicas at consistency-level ONE, demonstrating that if you can ease back your consistency requirements then you don’t have to maintain so many copies of your data just to achieve consensus.
________________
Multi DC
Multi DC Cassandra clusters allow some special scenarios, which when combined with the right application can provide both partition-tolerance (for the WAN connection) but strong-consistency at a local level. This involves having enough replicas at each site to use the LOCAL_QUORUM consistency level, where only replicas at the local DC are involved in queries. If you are able to consistently shard your traffic (say on geographical boundaries) then under normal operations you wouldn’t require global QUORUM queries, but you still have the ability to re-route that traffic between DCs and know that all but the last fraction of a percent of recently written data will be in place.


Replicas per DC
	Consistency-level
	AP Tolerant (WAN)?
	Local Consistency?
	1
	ONE / LOCAL_ONE
	yes
	no
	1
	LOCAL_QUORUM
	n/a
	n/a
	2
	ONE / LOCAL_ONE
	yes
	no
	2
	LOCAL_QUORUM
	n/a
	n/a
	3
	ONE / LOCAL_ONE
	yes
	no
	3
	LOCAL_QUORUM
	yes
	yes
	

The bottom line
To achieve both high-availability and partition-tolerance you will need to sacrifice consistency.


AP systems would generally make use of the following consistency-levels:
* ONE
* LOCAL_ONE
* LOCAL_QUORUM