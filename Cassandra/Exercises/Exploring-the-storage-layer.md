Exercise: Exploring the storage layer
=====================================


Overview
--------
In this exercise you will create a schema, insert data, observe how Cassandra stores it on disk, and understand what this means for reads.


Pre-requisites
--------------
* A working single-node Cassandra cluster (assuming that the container is called "cassandra-1").
Goals
* To understand how data is written to Cassandra
* To understand how Cassandra manages data on-disk over time
* To understand the relationship between write-behaviour and read-efficiency


Useful Commands
---------------
### Flush data from memtables/commitlogs to disk

``` docker exec -it <container-name/id> nodetool flush <keyspace>```

### Run "cqlsh" in one of your Cassandra containers

```docker exec -it <container-name/id> cqlsh -C```

### Find out which files on disk are hosting a table

```docker exec -it <container-name/id> sstableutil <keyspace> <table>```


Steps
-----


### Prepare a simple schema
We’ll use a very simple one-to-one table as an example schema based on a user-account database. Schema-definition and data-manipulation is done through the "cqlsh" utility (the command to run this is listed above).


#### Create a keyspace
This CQL statement will create a new keyspace called "examples" using the simple replication-strategy with one replica.

```CREATE KEYSPACE examples WITH replication = {'class': 'SimpleStrategy', 'replication_factor': '1'};```


#### Create a Table
This CQL statement will create a new table called "users", holding simple user account objects.

```
CREATE TABLE examples.users (
  user_name varchar,
  password varchar,
  country varchar,
  PRIMARY KEY (user_name)
);
```


#### Check which files are holding your data
You can now use the sstableutil command to check which files are holding data for your new table (of course this will return nothing right now, because you haven’t inserted any data yet).

```docker exec -it cassandra-1 sstableutil examples users```


### See some data get written to the disk
You will now insert some test data and see that it gets written to the disk. Again, the CQL statements are run in "cqlsh".


#### Insert test data
Insert one user into the users table. For the benefit of further steps please use these exact values.

```INSERT INTO examples.users (user_name, password, country) VALUES ('some-user', 'users-poor-password', 'uk');```


#### Check which files are holding your data
Use the same "sstableutil" command to list the files holding data for this table. Unless you’ve waited a VERY long time since the previous step, there will still be no files on disk for this table. Why has this happened?
* Your data is currently held [in-memory](https://wiki.apache.org/cassandra/MemtableSSTable) and in the [commit-logs](http://wiki.apache.org/cassandra/Durability).
* Time and / or throughput will eventually cause this to be flushed to an [SSTable](http://wiki.apache.org/cassandra/ArchitectureSSTable) file.
* We can also manually cause your data to be [flushed](https://docs.datastax.com/en/cassandra/2.1/cassandra/tools/toolsFlush.html) to disk.
* Even though your data is currently not in an SSTable file it CAN still be queried - don’t worry!


#### Flush your data to disk
Use the "nodetool flush" command to force your table to be flushed to disk, then run the "sstableutil" command again.

```docker exec -it cassandra-1 nodetool flush examples users```


### See how read queries work
You will now have a chance to see how read-queries work against data on disk.


##### Enable Tracing
CQL / cqlsh offers a powerful "tracing" feature (the closest to an "explain" query you’ll get in Cassandra), which can show how your queries are being fulfilled and help to understand the performance implications of your queries interaction with storage.

```TRACING ON;```


#### Read the data you previously inserted
You can now run a SELECT query in the tracing-enabled CQLSH session, paying attention to the number of SSTables involved. Of course we already know that this query will be served by one SStable.

```SELECT * FROM examples.users WHERE user_name = 'some-user';```


#### Update the record
Now change the password for the user we created earlier.

```UPDATE examples.users SET password = 'SuP3r4W3s0m3' WHERE user_name = 'some-user';```


#### Flush the table data again
Use the "nodetool flush" command (in another window) to force your table to be flushed to disk, then run the "sstableutil" command again. You’ll see that you now have 2 SSTables (and their associated metadata).

```docker exec -it cassandra-1 nodetool flush examples users```


#### Read the data again
Run the SELECT query again in your tracing-enabled cqlsh session. It will now tell you that your single-partition read query required data to be merged from two files on disk. 

```SELECT * FROM examples.users WHERE user_name = 'some-user';```

Congratulations - you’ve now got an inefficient read-path.


#### Use nodetool to confirm that your data is fragmented

```docker exec -it cassandra-1 nodetool tablehistograms examples users```


### Re-optimising the read-path
You could keep updating this record (each time creating more sstables), and eventually the read performance will deteriorate. This is obviously not good! What can be done about this?


#### Perform a forced compaction
Cassandra will periodically attempt to bring order to the fragmented chaos by concatenating SSTables together until (ideally) each partition lives entirely within one file again. These will be triggered by various thresholds, and generally it is best not to interfere with compactions (or to trigger them manually). Over-aggressive compaction can cause imbalances further down the track.

In this case you should trigger a manual compaction anyway, to see how it works.

```docker exec -it cassandra-1 nodetool compact examples users```

If you run the "sstableutil" command again you will now notice that there is only one file again. It is worth noting that both of the old files (numbers 1 & 2) are completely gone, replaced by number 3.


#### Read the data again
Run the SELECT query again in your tracing-enabled cqlsh session. It will now tell you that your single-partition read query was served by one SSTable (number 3).

```
TRACING ON;
SELECT * FROM examples.users WHERE user_name = 'some-user';
```

___Order is restored!___


Finishing up
------------
You have just witnessed first-hand how data gets written into Cassandra, and seen that data is not modified "in-place" - instead all modifications are kept until a compaction occurs.
