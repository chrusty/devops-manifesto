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
### Table scans
Cassandra's scaling model is based on the idea of sharding the responsibility for servicing queries between more machines. Scanning tables works completely against this concept - this type of query MUST involve every token-range in the entire cluster, and adding more nodes will in fact only make the performance worse.

This is why I say that ```SELECT * FROM <table>;``` should be considered "_illegal_". 


### Secondary indices



Scaling for performance
-----------------------



Scaling for storage capacity
----------------------------


Scaling for geographic distribution
-----------------------------------
