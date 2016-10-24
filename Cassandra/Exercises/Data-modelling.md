Exercise: Data-modelling
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
* Get a feel for the concept "each partition can behave like a small table-within-a-table"


Pre-requisites
--------------
* A working multi-node Cassandra cluster as prepared in the clustering exercise (assuming that the containers are called "cassandra-1", "cassandra-2", "cassandra-3").


Useful Commands
---------------
### Run CQLSH:

```docker exec -it <container-name/id> cqlsh -C```

### Enable tracing (CQLSH):

```TRACING ON;```


Steps
-----


### One-to-one
In this section you will interact with the simplest way to model data with Cassandra. "One-to-one" means "one partition-key to one object". In this case we will be modelling a simple username database, where each user is stored against their own partition-key.


#### Create a schema & test data
Run these commands within CQLSH. _Note that we're using replication_factor=1 here, because this will emphasise the performance impact of your queries later on_.

Note that the schema uses only one field for the "PRIMARY KEY". It means that for this schema the partition key is just the "user_name".

```
CREATE KEYSPACE examples WITH replication = {'class': 'SimpleStrategy', 'replication_factor': '1'};

CREATE TABLE examples.users (
  user_name varchar,
  password varchar,
  country varchar,
  PRIMARY KEY (user_name)
);
```


#### Insert some data
Insert some user accounts into the table you've just made:

```
INSERT INTO examples.users (user_name, password, country) VALUES ('chris', 'cruft123', 'nz');
INSERT INTO examples.users (user_name, password, country) VALUES ('geno', 'letmein', 'uk');
INSERT INTO examples.users (user_name, password, country) VALUES ('thomas', 'schnell', 'de');
```


#### Query the data
Now perform some queries on the data you've inserted. With tracing enabled you will be able to see how many partitions were involved. Also take note of any warnings, and the amount of time taken to service each query.

##### Enabled tracing

```
TRACING ON;
```

##### Single-partition

```
SELECT * FROM examples.users WHERE user_name = 'chris';
```

##### Table-scan

```
SELECT * FROM examples.users;
```

##### Filtering

```
SELECT * FROM examples.users WHERE country = 'uk';
SELECT * FROM examples.users WHERE country = 'uk' ALLOW FILTERING;
```


#### Features of this type of index
The one-to-one index is conceptually simple, and theoretically allows you to scale forever. However, we need to be aware of its shortcomings:
* We are only able to query one specific user at a time. This is not a model that allows you to do things like "list" users.
* We could also not do things like "search" (for example, find all of the users in the UK) without using secondary indexes or allowing filtering (both of which are bad choices).


### One-to-many
In this section you will get a chance to use the one-to-many index. "One-to-many" means "one partition-key to many objects". In this case we will be modelling a denormalised secondary index, where each user is stored against their countries partition-key (providing a better way of asking the "find all of the users in the UK" query discussed in the previous section).

Note that the schema now specifies a more complicated "PRIMARY KEY". This example uses the "country" field as the partition-key (in double parentheses), and the "user_name" field as a clustering-column.


#### Create a schema & test data
Run these commands within CQLSH. _Note that we're using replication_factor=1 here, because this will emphasise the performance impact of your queries later on_.

```
CREATE TABLE examples.users_by_country (
  user_name varchar,
  password varchar,
  country varchar,
  PRIMARY KEY ((country), user_name)
);
```


#### Insert some data
Insert some user countries into the table you've just made:

```
INSERT INTO examples.users_by_country (user_name, password, country) VALUES ('chris', 'cruft123', 'nz');
INSERT INTO examples.users_by_country (user_name, password, country) VALUES ('nigel', 'europe456', 'uk');
INSERT INTO examples.users_by_country (user_name, password, country) VALUES ('boris', 'whatever789', 'uk');
INSERT INTO examples.users_by_country (user_name, password, country) VALUES ('david', 'bacon4me', 'uk');
INSERT INTO examples.users_by_country (user_name, password, country) VALUES ('thomas', 'schnell', 'de');

```


#### Query the data
Now perform some queries on the data you've inserted. With tracing enabled you will be able to see how many partitions were involved. Also take note of any warnings, and the amount of time taken to service each query.

##### Enabled tracing

```
TRACING ON;
```

##### Single-partition

```
SELECT * FROM examples.users_by_country WHERE country = 'uk';
```

##### Multi-partition

```
SELECT * FROM examples.users_by_country WHERE country IN ('uk', 'de');
```

##### Table-scan

```
SELECT * FROM examples.users_by_country;
```

##### Filtering

```
SELECT * FROM examples.users_by_country WHERE country = 'uk' AND user_name > 'cameron';
```


#### Features of this type of index
The one-to-many index makes use of Cassandra's underlying "wide-row" storage to provide some extra flexibility over the one-to-one model. However, we again need to be aware of its shortcomings:
* We are now able to query entire lists of user-accounts according to their country, while only hitting one partition.
* We can also filter & sort users with a list (known as a "slice" in Cassandra).
* We are still not able to list all users without involving a table-scan.
* Why couldn't we just have a country called "all", put all of the users in there, then get the listing and sorting and slicing? If we did that then all of our queries would be served by the same partition. It will NEVER distribute or scale.
* Because we don't know which country a user is in _ahead of time_, we still need to maintain both the "users" and "users_by_country" tables. This means that we need to insert into both places every time we add a user account, effectively using twice the storage.


### Time-series
In this section you will get a chance to use the time-series index. It builds on the "one-to-many" index we just explored, but this time the clustering-column will be a timestamp (time-series data is usually organised by timestamps). We will also use a [compound partition-key](http://docs.datastax.com/en/cql/3.3/cql/cql_using/useCompoundPrimaryKeyConcept.html) consisting of two attributes ("user_name" and "bucket"). This allows us to spread our time-series indices over several partitions. We will also include a "description" field to explain what has been done each time. We will also store the timeseries entries in reverse order (DESC).


#### Create a schema & test data
Run these commands within CQLSH. _Note that we're using replication_factor=1 here, because this will emphasise the performance impact of your queries later on_.

```
CREATE TABLE examples.users_history (
  user_name varchar,
  bucket date,
  timestamp timestamp,
  password varchar,
  country varchar,
  description varchar,
  PRIMARY KEY ((user_name, bucket), timestamp)
)
WITH CLUSTERING ORDER BY (timestamp DESC);
```


#### Insert some data
Insert some user history events into the table you've just made:

```
INSERT INTO examples.users_history (bucket, user_name, timestamp, password, country, description) VALUES ('2016-10-04', 'chris', '2016-10-04 12:34', 'cruft123', 'nz', 'user created');
INSERT INTO examples.users_history (bucket, user_name, timestamp, password, country, description) VALUES (toDate(now()), 'chris', toTimestamp(now()), 'cruft123', 'uk', 'country changed');
INSERT INTO examples.users_history (bucket, user_name, timestamp, password, country, description) VALUES (toDate(now()), 'chris', toTimestamp(now()), 'newPassw0rd', 'uk', 'password changed');
INSERT INTO examples.users_history (bucket, user_name, timestamp, password, country, description) VALUES ('2016-10-06', 'thomas', '2016-10-06 15:46', 'schnell123', 'de', 'user created');
INSERT INTO examples.users_history (bucket, user_name, timestamp, password, country, description) VALUES (toDate(now()), 'thomas', toTimestamp(now()), 'schnell123', 'uk', 'country changed');
INSERT INTO examples.users_history (bucket, user_name, timestamp, password, country, description) VALUES (toDate(now()), 'thomas', toTimestamp(now()), 'sauerkraut', 'uk', 'password changed');
INSERT INTO examples.users_history (bucket, user_name, timestamp, password, country, description) VALUES ('2016-12-24', 'thomas', '2016-12-24 09:23', 'currywurst', 'uk', 'merry christmas');
```


#### Query the data
Now perform some queries on the data you've inserted. With tracing enabled you will be able to see how many partitions were involved. Also take note of any warnings, and the amount of time taken to service each query.

##### Enabled tracing

```
TRACING ON;
```

##### Single-partition

```
SELECT * FROM examples.users_history WHERE user_name = 'chris' AND bucket = toDate(now());
SELECT * FROM examples.users_history WHERE user_name = 'thomas' AND bucket = toDate(now());
```

##### Multi-partition

```
SELECT * FROM examples.users_history WHERE user_name = 'chris' AND bucket IN ('2016-10-04', toDate(now()));
SELECT * FROM examples.users_history WHERE user_name = 'thomas' AND bucket IN ('2016-10-06', toDate(now()), '2016-12-24');

```

##### Table-scan

```
SELECT * FROM examples.users_history;
```

##### Filtering

```
SELECT * FROM examples.users_history WHERE user_name = 'thomas' AND bucket IN ('2016-10-06', toDate(now()), '2016-12-24') AND timestamp > toUnixTimestamp(toDate(now()));
```


#### Features of this type of index
The timestamp index builds on top of the one-to-many approach, making use of Cassandra's underlying "wide-row" storage with the addition of composite primary keys. However, we again need to be aware of its shortcomings:
* We can now handle large volumes of time-series data, while allowing older parts of the dataset to "cool down" in less frequently used buckets.
* The size of the buckets is still up to us however. Buckets that are too large will cause issues if we attempt to query them all (imagine trying to store every tweet for a year in one partition). Conversely, buckets that are too small will involve too many partitions when trying to re-assemble the history of your data.


Finishing up
------------
Hopefully by this point you have an understanding of three powerful basic indexes which are often used with Cassandra.


The important points to take away are:
* Queries work best when you model your data against what Cassandra can do well
* Scalability and performance are directly related to how you model your data
* It may not always be possible to model your data for Cassandra
