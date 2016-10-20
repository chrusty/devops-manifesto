Cassandra: Scaling considerations
=================================


Introduction
------------
This document is intended to provide an introduction to some of the concepts of scaling Cassandra.


Scaling in general
------------------
### Things to be careful of
There are a few things that can cause issues during scaling exercises. Take your time to plan properly, and particularly watch out for the following scenarios.

#### Scaling too quickly
When working with Cassandra clusters you should always be aware of your failure tolerance. This applies to scaling operations too - because a new node will not be able to serve queries until it has finished joining / streaming data, it should be considered as a "failed" node until it has all of the data required to participate in serving queries.

___For this reason, if you only have 3 replicas and are using QUORUM queries, you can only ever introduce one new node at a time without causing a data outage.___ Of course, larger numbers of replicas allow more nodes to be worked on at the same time.


#### Scaling too late
Due to the fact that you need to add/remove nodes slowly and that it can take a long time for new nodes to join/leave, it can take a long time to scale clusters up or down. For this reason, unless you have either a tiny amount of data or extremely fast network and storage, ___it is better to scale pro-actively (ahead of time) than reactively___ (when you already need the extra capacity).


Scaling for performance
-----------------------


Scaling for capacity
--------------------