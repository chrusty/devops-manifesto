Exercise: Replication & consistency
===================================


Overview
--------
In this exercise you will explore how data is distributed in a multi-node cluster, how data is replicated, and how this works hand-in-hand with consistency levels.


Goals
-----
* Understand how partitions are distributed using tokens for their keys
* Experience the relationship between replication-factor and distribution
* Explore failure scenarios using different combinations of replication and consistency
* Witness how inconsistent data can be repaired automatically and manually


Pre-requisites
--------------
* A working multi-node Cassandra cluster as prepared in the clustering exercise (assuming that the containers are called “cassandra-1", “cassandra-2", “cassandra-3").


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


### Replication-factor 1
The first section works with replication-factor 1, where each partition will randomly be assigned to one of your three nodes. We will run a few experiments to track down our data, and cause a small outage.


#### Create a schema & test data
Run these commands within CQLSH.
```
CREATE KEYSPACE rf_one WITH replication = {'class': 'SimpleStrategy', 'replication_factor': '1'};
CREATE TABLE rf_one.cruft (
  kruftkey varchar,
  description varchar,
  crufty boolean,
  PRIMARY KEY (kruftkey)
);
INSERT INTO rf_one.cruft (kruftkey, description, crufty) VALUES ('testing', 'test key', true);
```


#### Find the token
Until I can find the algorithm to calculate a Murmur3 token for a given key, we just have to trust CQLSH.
```SELECT TOKEN(kruftkey) FROM rf_one.cruft WHERE kruftkey='testing';```


#### Find which node owns that token (the hard way)
Use the nodetool command to print a list of all the token-ranges for your cluster, and find where your token fits in. The number in the “token" column are the upper-boundaries of the token ranges.
```docker exec -it cassandra-1 nodetool ring```


#### Find which node owns that token (the easy way)
Nodetool has a command which allows you to find which node(s) own your data (by providing the keyspace, table and key).
```nodetool getendpoints rf_one cruft testing```


#### Inspect the sstable
Now you should be able to run bash in the appropriate cassandra container, find the sstable directory for your table, use “apt-get install binutils" to install the “strings" binary, flush the table to disk, and use “strings" to print some contents of the sstable.

##### Run an interactive bash shell in the container
```docker exec -it cassandra-x bash```

##### Install strings and check the sstable-file
```
apt-get update && apt-get install binutils
nodetool flush rf_one
sstableutil rf_one cruft
strings /var/lib/cassandra/data/rf_one/cruft-*/mb-1-big-Data.db
```


#### Insert 9 more rows
Now use CQLSH to insert 9 more rows (hopefully that is enough rolls of the dice to ensure that you end up with some data on each of your 3 nodes).
```
USE rf_one;
INSERT INTO cruft (kruftkey, description, crufty) VALUES ('testing1', 'test key', true);
INSERT INTO cruft (kruftkey, description, crufty) VALUES ('testing2', 'test key', true);
INSERT INTO cruft (kruftkey, description, crufty) VALUES ('testing3', 'test key', true);
INSERT INTO cruft (kruftkey, description, crufty) VALUES ('testing4', 'test key', true);
INSERT INTO cruft (kruftkey, description, crufty) VALUES ('testing5', 'test key', true);
INSERT INTO cruft (kruftkey, description, crufty) VALUES ('testing6', 'test key', true);
INSERT INTO cruft (kruftkey, description, crufty) VALUES ('testing7', 'test key', true);
INSERT INTO cruft (kruftkey, description, crufty) VALUES ('testing8', 'test key', true);
INSERT INTO cruft (kruftkey, description, crufty) VALUES ('testing9', 'test key', true);
```


#### Stop one of your cassandra nodes and try to query your data
Use the docker stop command to temporarily stop one of your node, then use cqlsh to query each of your rows in turn. Notice that you can still query the ones which are hosted on nodes that are still up, and the the outage we have caused isn’t a complete system outage - merely the data hosted on the missing node.

__Make sure you start the node again before the next section__


### Replication-factor 2
In this section we will experiment with storing 2 replicas instead of one, and see what kind of extra availability this can deliver.


#### Create a schema & test data
Note the different "replication_factor".
```
CREATE KEYSPACE rf_many WITH replication = {'class': 'SimpleStrategy', 'replication_factor': '2'};
CREATE TABLE rf_many.cruft (
  kruftkey varchar,
  description varchar,
  crufty boolean,
  PRIMARY KEY (kruftkey)
);
INSERT INTO rf_many.cruft (kruftkey, description, crufty) VALUES ('testing', 'test key', true);
INSERT INTO rf_many.cruft (kruftkey, description, crufty) VALUES ('exercise', 'another test key', true);
```


#### Find which nodes own that token
Use the same nodetool command to find which node(s) own some of this new data (by providing the keyspace, table and key).
```nodetool getendpoints rf_many cruft testing```


#### Insert 9 more rows
Now use CQLSH to insert 9 more rows (hopefully that is enough rolls of the dice to ensure that you end up with some data on each of your 3 nodes).
```
USE rf_many;
INSERT INTO cruft (kruftkey, description, crufty) VALUES ('testing1', 'test key', true);
INSERT INTO cruft (kruftkey, description, crufty) VALUES ('testing2', 'test key', true);
INSERT INTO cruft (kruftkey, description, crufty) VALUES ('testing3', 'test key', true);
INSERT INTO cruft (kruftkey, description, crufty) VALUES ('testing4', 'test key', true);
INSERT INTO cruft (kruftkey, description, crufty) VALUES ('testing5', 'test key', true);
INSERT INTO cruft (kruftkey, description, crufty) VALUES ('testing6', 'test key', true);
INSERT INTO cruft (kruftkey, description, crufty) VALUES ('testing7', 'test key', true);
INSERT INTO cruft (kruftkey, description, crufty) VALUES ('testing8', 'test key', true);
INSERT INTO cruft (kruftkey, description, crufty) VALUES ('testing9', 'test key', true);
```


#### Shut down one node, try to read your data
You should be able to read all of your data in the new keyspace, even with one node out of action. This is because the default consistency-level is ONE.
```
SELECT * FROM rf_many.cruft WHERE kruftkey = 'testing1';
SELECT * FROM rf_many.cruft WHERE kruftkey = 'testing2';
SELECT * FROM rf_many.cruft WHERE kruftkey = 'testing3';
```

#### Shut down another node, try to read your data
You should still be able to read some of your data, but there is a percentage which is offline now.
```
SELECT * FROM rf_many.cruft WHERE kruftkey = 'testing1';
SELECT * FROM rf_many.cruft WHERE kruftkey = 'testing2';
SELECT * FROM rf_many.cruft WHERE kruftkey = 'testing3';
```

__Make sure you start all of your nodes again before the next section__


### Replication-factor 3
In this section we will take our first steps with both high-availability and strong-consistency. We need all 3 nodes up and running again.


#### Alter the previous keyspace to have one more replica
```ALTER KEYSPACE rf_many WITH replication = {'class': 'SimpleStrategy', 'replication_factor': '3'};```


#### Repair the keyspace to ensure that we have 3 replicas
```docker exec -it cassandra-1 nodetool repair rf_many```


#### Shut down 2 nodes and prove that you can still query all of the data
Now that we have data everywhere we can shut down 2 nodes and still run queries at CL=1.
```docker stop cassandra-2 cassandra-3```


#### Start the nodes again, and change consistency
Now it is time to try some stronger consistency-levels. Try “QUORUM" and “ALL" with tracing enabled and compare the performance to “ONE".
```
CONSISTENCY QUORUM
CONSISTENCY ALL
CONSISTENCY ONE
```

#### Perform outage-testing with QUORUM queries
“QUORUM" queries are really the sweet spot with Cassandra. A combination of QUORUM writes and QUORUM reads allows no room for inconsistency, yet can keep working if a node is down. WIN! 

__Make sure you start all of your nodes again before the next section__


### Reconciliation
We will now try to cause some data-inconsistency, and see how Cassandra copes.


#### Delete some SSTables
We will manually delete the sstables for the rf_many.cruft table we created earlier, then restart cassandra to make it come up with no data for that table.

##### Run an interactive bash shell in the container
```docker exec -it cassandra-3 bash```

##### Delete the sstables
```
rm /var/lib/cassandra/data/rf_many/cruft-*/*
exit
```

##### Restart the container
```docker restart cassandra-3```


#### Query the data with CL=one
Once cassandra has loaded, use cqlsh to query the row we inserted before. You will probably not get a response!
```
CONSISTENCY ONE
SELECT * FROM rf_many.cruft WHERE kruftkey = 'testing';
```


#### Query the data with CL=quorum
All is not lost... we can use a higher consistency-level.
```
CONSISTENCY QUORUM
SELECT * FROM rf_many.cruft WHERE kruftkey = 'testing';
```


#### Try again with CL=one
And now Cassandra’s background consistency-reconciliation will have permanently repaired this record on cassandra-3.
```
CONSISTENCY ONE
SELECT * FROM rf_many.cruft WHERE kruftkey = 'testing';
```


#### Repair the rest of the data
Now use the nodetool repair command to repair the table before checking the other rows.
```nodetool repair rf_many cruft -full```


#### Check another row
Now check one of the other rows. After being repaired it should return data the first time.
```
CONSISTENCY ONE
SELECT * FROM rf_many.cruft WHERE kruftkey = 'exercise';
```


Finishing up
------------
Hopefully by this point you have a better understanding of how data is replicated and distributed around a Cassandra cluster.


The important points to take away are:
* An understanding of how data gets distributed according to the replication factor
* Appreciating that multiple replicas can be queried using different consistency levels
* A memory of having seen Cassandra automatically repair inconsistent data
* The knowledge that you can always fix inconsistencies using a repair
