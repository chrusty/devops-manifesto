Exercise: Distributed counters
==============================


Overview
--------
In this exercise you will practise using Cassanda's distributed-counter feature.


Pre-requisites
--------------
* A working single-node Cassandra cluster (assuming that the container is called "cassandra-1").

### Goals
* Create a schema for counters and see how to work with them using CQL
* Understand the problem they are trying to solve
* Understand their limitations


### Run "cqlsh" in one of your Cassandra containers
```
docker exec -it <container-name/id> cqlsh -C
```


Background
----------

Cassandra is designed around being able to work with data without having to involve all of the nodes in the cluster. While this is fine if you want to simply overwrite values, it is not so simple when you need to know the value you're changing before-hand (this pattern is known as "read-before-write"). Beyond "read-before-write", there is another problem that manifests itself when someone else modifies the value between your read and write queries (meaning you would need to externally lock the record first). This process is grossly inefficient, slow, and can strangly your beautifully parallel processing through a single bottle-neck. _Surely there is another way to do this?_

It turns out that for simple additions and subtractions there is another way you could approach this problem. Simply record the _delta_ of the value, and add them up later. So a counter is actually a history of additions and subtractions to a named value which is summed up each time it is read by a query. Compactions then collapse this history down to a single value again, ready for more history to be added on top.

A neat solution.


Steps
-----


### Prepare a simple schema
We’ll use a very simple one-to-one table as an example schema. Schema-definition and data-manipulation is done through the "cqlsh" utility (the command to run this is listed above).


#### Create a keyspace
This CQL statement will create a new keyspace called "examples" using the simple replication-strategy with one replica.
```
CREATE KEYSPACE IF NOT EXISTS examples WITH replication = {'class': 'SimpleStrategy', 'replication_factor': '1'};
```

#### Create a "hit-counter" table
This CQL statement will create a new table called "hit_counter", holding a list of hits for imaginary WWW requests.
```
CREATE TABLE examples.hit_counter (
  web_site varchar,
  url varchar,
  hits counter,
  PRIMARY KEY (web_site, url)
);
```


### See counters in action

#### Insert test data
```
UPDATE examples.hit_counter SET hits = hits + 1 WHERE web_site = 'cassandra-cruft.com' AND url = '/how-to-use-counters.html';
UPDATE examples.hit_counter SET hits = hits + 3 WHERE web_site = 'cassandra-cruft.com' AND url = '/how-to-use-counters.html';
UPDATE examples.hit_counter SET hits = hits + 6 WHERE web_site = 'google.com' AND url = '/search/can-counters-be-subtracted';
UPDATE examples.hit_counter SET hits = hits - 4 WHERE web_site = 'google.com' AND url = '/search/can-counters-be-subtracted';
UPDATE examples.hit_counter SET hits = hits - 8 WHERE web_site = 'cassandra-cruft.com' AND url = '/negative-counters.html';
```

#### Query the data to see the counts
```
SELECT * FROM examples.hit_counter WHERE web_site = 'cassandra-cruft.com';
SELECT * FROM examples.hit_counter WHERE web_site = 'google.com';
```


Finishing up
------------
You have now experienced how to use a new data-type with Cassandra. This is a very powerful solution to one of the difficult problems in computer science, but it does have its limitations. The main thing to be aware of is that Cassandra doesn't offer you the ability to "roll-back" a transaction (or "transactions" at all in the traditional sense). This exposes us to scenarios where a counter query makes it to a cluster, but the response never makes it back to the client. In this case the client is not aware if the query was successful or not, and will not know if the query should be retried.

___For this reason it is inadvisable to rely on counters where precise accuracy is required.___ However, where the numbers are large and a margin of error is acceptable it can be a very useful tool.
