Exercise: Data modelling
========================


Overview
--------
In this exercise you will get a chance to model data against 3 common Cassandra indexing patterns:
* one-to-one
* one-to-many
* time-series

For consistency, the examples will be taken from the "Data modelling" paper.


Goals
-----
* Create schemas for these indexing patterns
* Practise inserting data into them
* Understand how these indexing patterns help us to achieve single-partition queries


Pre-requisites
--------------
* A working multi-node Cassandra cluster as prepared in the clustering exercise (assuming that the containers are called "cassandra-1", "cassandra-2", "cassandra-3").


Useful Commands
---------------
### Find out which node(s) are responsible for a given key:

```docker exec -it <container-name/id> nodetool getendpoints```

### Find the token for a partition in CQLSH:

```SELECT TOKEN(user_name) FROM users WHERE user_name='some-user';```

### Find the data-distribution for a keyspace:

```docker exec -it <container-name/id> nodetool status <keyspace>```


Steps
-----


### One-to-one
In this section you will interact with the simplest way to model data with Cassandra. "One-to-one" means "one partition-key to one object". In this case we will be modelling a simple username database, where each user is stored against their own partition-key.


#### Create a schema & test data
Run these commands within CQLSH.

```
CREATE KEYSPACE modelling WITH replication = {'class': 'SimpleStrategy', 'replication_factor': '3'};

CREATE TABLE modelling.users (
  user_name varchar,
  password varchar,
  country varchar,
  PRIMARY KEY (user_name)
);
```


#### Insert some data
Insert some user accounts into the table you've just made:

```
INSERT INTO modelling.users (user_name, password, country) VALUES ('chris', 'cruft123', 'nz');
INSERT INTO modelling.users (user_name, password, country) VALUES ('geno', 'letmein', 'uk');
INSERT INTO modelling.users (user_name, password, country) VALUES ('thomas', 'schnell', 'de');
```


#### Query the data
Now perform some queries on the data you've inserted. With tracing enabled you will be able to see how many partitions were involved.

```
TRACING ON;
SELECT * FROM modelling.users WHERE user_name = 'chris';
```


#### Features of this type of index
The one-to-one index is conceptually simple, and theoretically allows you to scale forever. However, we need to be aware of its shortcomings:
* We are only able to query one specific user at a time. This is not a model that allows you to do things like "list" users.
* We could also not do things like "search" for users without using secondary indexes (for example, find all of the users in the UK).


Finishing up
------------
Hopefully by this point you have an understanding of three powerful basic indexes which are often used with Cassandra.


The important points to take away are:
* Queries work best when you model your data against what Cassandra can do well
* Scalability and performance are directly related to how you model your data
* It may not always be possible to model your data for Cassandra
