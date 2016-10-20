Cassandra: Data-modelling
=========================


Introduction
------------
This document is intended to provide an introduction to some of the concepts of modelling data to get the best out of Cassandra, and the main points to consider during this process. It also includes some example recipes for the types of models and indices you can safely achieve with Cassandra.


Considerations
--------------
### Work with Cassandra’s strengths
This is THE most important thing to keep in mind when modelling data for Cassandra. Any distributed database has to make certain compromises which give them special powers (and weaknesses). If you can’t model your data to the strengths of your chosen database then you will almost certainly be setting up some epic-fail for the future. I will outline some solid recipes for Cassandra based on some of these strengths which should be safe to use even at scale.


### Remember what "key/value store" means
Cassandra is primarily a key/value store, which for the point I’m trying to make should be interpreted as "a distributed database which is able to retrieve a value for a given key". Essentially it is a system designed to provide a hugely scalable primary-key index. Used in this (albeit simplistic) way, you can expect the performance characteristics to scale linearly with the number of nodes in your cluster.

___Cassandra will perform the best when you use it for single-partition queries___ - Avoid table-scans (ALWAYS), and multi-gets (where possible).


### Understand Cassandra’s underlying storage layer
Cassandra is highly optimised towards write performance. [This page](http://docs.datastax.com/en/cassandra/2.0/cassandra/dml/dml_write_path_c.html) explains the process in some detail (PLEASE READ), but suffice to say that in Cassandra _"writes are cheap, reads are expensive"_. On a well-tuned cluster you can expect write queries to be serviced in less than 1ms, and read-queries to be serviced somewhere around 2ms (depending on the underlying storage and I/O). This process can be described as _"log changes in the order they arrive, then flush them to more permanent files later in chunks, and even further down the track squash these files together to make read-performance suck a bit less"_.

#### Write throughput
While writes ARE cheap, eventually the result of writing lots of data into Cassandra is that compactions will be triggered. Compactions use a lot of sequential disk I/O, cause more frequent garbage accumulation and collection, and will generally adversely affect the performance of the rest of the operations running on a Cassandra node. For this reason, your write patterns will need to be taken into account when specing / scaling your clusters.

#### Read throughput
Done well, read performance can be quite consistent in Cassandra. Throw compactions & repairs and garbage-collections into the mix however, and your mileage can vary greatly. High read-throughputs can create a significant amount of in-memory garbage which the JVM (Cassandra is written in Java remember) needs to clear out from time-to-time. Again, your read patterns will have a massive impact on the cluster.

#### Continuous compactions
Cassandra will keep compacting a partition until it lives in one SSTable. Remember that each time you UPDATE a value, in reality Cassandra is just recording a newer value in a new SSTable, then compacting it back into one SSTable later. This operation involves sequentially reading and writing the entire partition out to a new file before the old ones can be removed. Although Cassandra doesn’t really stop you from doing so, it is not sustainable to be forever compacting a larger and larger partition together (so consider breaking your partitions up, probably by time).


### Don’t begin until you can answer these questions
The answers to these questions do not really suggest anything by themselves, but when taken together they can highlight some early signs of trouble. I recommend that anyone responsible for maintaining production Cassandra clusters asks these questions before hosting any new data.

#### When and how will data be written?
This is really about the frequency of WRITE queries, and their effect on compaction workloads.

#### When and how will data be read?
This is really about the frequency of READ queries, and their effect on garbage-collection.

#### How big will a partition get?
This will give an idea of the compaction overheads.

#### Will partitions be written to forever?
This combined with expected large partition sizes spells trouble.

#### How long will data live here for?
Will the overall dataset grow forever, or is an archiving policy in place?

#### How will data be removed?
Is it safe to apply a default TTL to this data, or do we need to maintain another index and trigger cleanup jobs later?

#### How well will the data be distributed around the cluster?
A sustainable (and scalable) data-model can never rely on one partition to store everything. This simply does not scale, and amplifies any performance issues the node hosting your partition may be having.


Safe Recipes
------------
At a previous company I initiated a project to create a standard library for our developers to use with Cassandra. It was a kind of ORM which exposed some of Cassandra’s strengths as classic recipes which people could use to store their data. The following list describes 3 of these recipes that most developers will find useful, and explanations are given as to why they work well (and what to be careful of).


### One to one
This is the most simple way to use Cassandra, and it is guaranteed to scale well. Simply put, each partition-key maps to one object (the table holds a list of objects with the same schema, and the objects are only ever referenced by their partition keys).

#### Example usage
This type of table could be used to host a database of user-accounts where the partition-key is the username, and the columns are the user attributes.

#### Example schema
```
CREATE TABLE examples.users (
  user_name varchar,
  password varchar,
  country varchar,
  PRIMARY KEY (user_name)
);
```

#### Example data
```
INSERT INTO examples.users (user_name, password, country) VALUES ('chris', 'cruft123', 'nz');
INSERT INTO examples.users (user_name, password, country) VALUES ('geno', 'letmein', 'uk');
INSERT INTO examples.users (user_name, password, country) VALUES ('thomas', 'schnell', 'de');
```

#### Example queries

##### Good:
This is a simple key/value query, what Cassandra was designed for:
```SELECT password from examples.users where user_name = 'chris';```

##### Bad:
This is a table-scan (involving ALL nodes / partition-ranges in the cluster):
```SELECT * from examples.users;```


### One to many
This recipe makes use of the _"each partition is like a mini-table with free ordering of rows"_ approach. Where the one-to-one table holds only one object, the one-to-many table holds a list of multiple objects (all with the same schema) against one partition-key. Each of the stored objects is addressable using their clustering-column(s).

#### Example usage
This type of table could be used to host a database of user-groups where the partition-key is the group-name, and the columns are the accounts belonging to the group.

#### Example schema
```
CREATE TABLE examples.groups (
  group_name varchar,
  user_name varchar,
  password varchar,
  country varchar,
  PRIMARY KEY ((group_name), user_name)
);
```

#### Example data
```
INSERT INTO examples.groups (group_name, user_name, password, country) VALUES ('admin', 'chris', 'cruft123', 'nz');
INSERT INTO examples.groups (group_name, user_name, password, country) VALUES ('coffee', 'chris', 'cruft123', 'nz');
INSERT INTO examples.groups (group_name, user_name, password, country) VALUES ('coffee', 'geno', 'letmein', 'uk');
INSERT INTO examples.groups (group_name, user_name, password, country) VALUES ('admin', 'thomas', 'schnell', 'de');
```

#### Example queries

##### Good:
This is a single-partition query which lists all usernames below "m" in the table-order:
```SELECT user_name FROM examples.groups WHERE group_name='admin' AND user_name < 'm';```

##### Bad:
This is another table-scan (involving ALL nodes / partition-ranges in the cluster):
```SELECT group_name from examples.groups;```


### Time-Series
The time-series recipe is an important one for Cassandra (as this is a common use-case for this technology). Again it makes use of the "each partition is like a mini-table with free ordering of rows" approach, but it is also sympathetic to the potential compaction overheads created by this pattern. The main difference here is that since time-series data is primarily indexed by time, we can use the timestamps to store this type of index across several partitions (where the one-to-many index is stored against one partition).

One thing to keep in mind with time-series is the bucket-size. There is no rule-of-thumb here, as it depends entirely on your application and workload. The idea of buckets is to avoid having every time-series entry on one partition: this doesn’t distribute around the cluster properly, and will result in partitions that get bigger and bigger forever (eventually compactions will grind your cluster to a halt).

#### Example usage
Time-series indices are useful for applications such as monitoring, logging, event-processing and comms. Even financial transactions can be best stored as time-series, for example _"show me all of the transactions performed against this account during the month of September 2016"_.

#### Example schema
```
CREATE TABLE examples.users_history (
  bucket date,
  user_name varchar,
  timestamp timestamp,
  timeuuid timeuuid,
  password varchar,
  country varchar,
  description varchar,
  PRIMARY KEY ((bucket, user_name), timestamp)
)
WITH CLUSTERING ORDER BY (timestamp DESC);
```

#### Example data
```
INSERT INTO examples.users_history (bucket, user_name, timestamp, timeuuid, password, country, description) VALUES ('2016-10-04', 'chris', '2016-10-04 12:34', now(), 'cruft123', 'nz', 'user created');
INSERT INTO examples.users_history (bucket, user_name, timestamp, timeuuid, password, country, description) VALUES (toDate(now()), 'chris', toTimestamp(now()), now(), 'cruft123', 'uk', 'country changed');
INSERT INTO examples.users_history (bucket, user_name, timestamp, timeuuid, password, country, description) VALUES (toDate(now()), 'chris', toTimestamp(now()), now(), 'newPassw0rd', 'uk', 'password changed');
```

#### Example queries

##### Good:
This is a single-partition query which lists all history for a user in a given bucket:
```SELECT * FROM examples.users_history WHERE bucket = toDate(now()) AND user_name = 'chris';```

##### Not so good:
This is a multi-partition query which lists all history for a user later than a certain time-stamp:
```SELECT * FROM examples.users_history WHERE bucket IN ('2016-10-04', toDate(now())) AND user_name = 'chris' AND timestamp > '2016-10-04 13:00';```
