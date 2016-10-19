Exercise: Backup & restore
==========================

Overview
--------
In this exercise you will practise backing up and restoring data in a Cassandra cluster.

Goals
-----
* Use the stress-test to create some data (we need something to backup)
* Backup some data by hand
* Use the data you’ve backed up to build a new cluster

Pre-requisites
--------------
* Docker installed on your machine
* Internet connectivity (for retrieving Docker images)
* A functioning 3-node cluster (as in previous exercises)

Useful Commands
---------------
### Make a snapshot
```docker exec -it <container-name/id> nodetool snapshot```

### Copy a directory out of a container
```docker cp <container-name/id>:/path/to/directory target```


Steps
-----

### Create some data
There is no point backing up an empty cluster, so the first thing to do is create some data!

#### Create a keyspace
Create a keyspace using CQLSH and manually insert some data. This keyspace will have 3 replicas.
```
CREATE KEYSPACE examples WITH replication = {'class': 'SimpleStrategy', 'replication_factor': '3'};


CREATE TABLE examples.users (
  user_name varchar,
  password varchar,
  country varchar,
  PRIMARY KEY (user_name)
);


INSERT INTO examples.users (user_name, password, country) VALUES ('user1', 'password1', 'uk');
INSERT INTO examples.users (user_name, password, country) VALUES ('user2', 'password2', 'uk');
INSERT INTO examples.users (user_name, password, country) VALUES ('user3', 'password3', 'uk');
```

#### Auto-generate an additional keyspace
Cassandra comes packaged with a built-in stress-testing tool. Aside from deriving performance benchmarks, this is also a handy way to automatically create some extra data. This keyspace will only have 1 replica.
```docker exec -it cassandra-1 cassandra-stress write n=10000 -rate threads=60 limit=120/s -node datacenter=datacenter1```

#### Check how many records were written
The stress-test made a keyspace called “keyspace1”, and a table called “standard1”. The command you’re about to run on it should NEVER be used on a regular basis. In fact, don’t even tell anyone I showed you this.
```SELECT COUNT(*) FROM keyspace1.standard1 LIMIT 100000;```


### Backup the data
We will now use some simple commands to backup your data. Due to the immutable nature of Cassandra’s on-disk storage format, it is relatively simply to back your data up - simply take the files from disk (no need to pause or stop the process first).

#### The schema
We need to be prepared to completely rebuild a cluster from the ground up, so just having the data-files is not enough to achieve this! We also need the schema - this command will dump the user-defined schema to a file on your docker host. You only need to do this once, as the schema will be the same on any node.
```docker exec -it cassandra-1 cqlsh -e 'DESC SCHEMA;' >schema.cql```

#### The data (in place)
As you should remember from earlier exercises, we will need to flush data to disk before we can see the SSTable files (“nodetool flush”, remember?). Once that is done (on all 3 nodes) you can use Docker's "copy" command to copy Cassandra’s entire data-directory from the containers onto your host’s filesystem.
```
docker exec -it cassandra-1 nodetool flush;
docker cp cassandra-1:/var/lib/cassandra/data cassandra-1;
docker exec -it cassandra-2 nodetool flush;
docker cp cassandra-2:/var/lib/cassandra/data cassandra-2;
docker exec -it cassandra-3 nodetool flush;
docker cp cassandra-3:/var/lib/cassandra/data cassandra-3;
```

#### The data (snapshots)
Cassandra also offers the ability to quickly make a “snapshot” of your data, and on a production cluster this is probably the best way to go. The snapshot command automatically flushes data to disk too, so you don’t need to worry about that step. These steps should be repeated for each cassandra container

##### Run an interactive bash shell in the "cassandra-1" container
```docker exec -it cassandra-1 bash```

##### Make a snapshot called "exercise"
```
nodetool snapshot --tag=exercise
tar -zcvf snapshot.tar.gz /var/lib/cassandra/data/*/*/snapshots/exercise
nodetool clearsnapshot
exit
```

##### Copy the snapshot to your docker-host
```docker cp cassandra-1:snapshot.tar.gz cassandra-1.snapshot.tar.gz```

#### Capture some evidence
You should now have a directory full of SSTables for each of your cassandra containers. When I did this on my machine these came out to about 2MB each, not exactly big data. Capture the output of the “nodetool status” command and the “nodetool ring” commands, just so we have something to compare once we’ve restored this data to a new cluster. You can also use the status command to check the data-distribution for these two keyspaces:

##### The "examples" keyspace
```docker exec -it cassandra-1 nodetool status examples```

##### The "keyspace1" keyspace
```docker exec -it cassandra-1 nodetool status keyspace1```

Note that each node has 100% of the data for “examples”, but only a rough third of “keyspace1”. Note that this 33.33% is randomly distributed.

#### Go ahead - destroy the cluster
You’ve now got a full backup of the cluster on your docker host machine. Stop and delete the 3 containers for your cluster, then build a new empty one.

##### Stop the cluster
```docker stop cassandra-1 cassandra-2 cassandra-3```

##### Delete the containers
```docker rm cassandra-1 cassandra-2 cassandra-3```


### Restore the data
Now it is time to restore the data. Unfortunately restoring from snapshots is a little clunky and involves moving data around. Restoring from the “in-place” backup is more straight-forward, but snapshots are probably more realistic for a production cluster.

#### Restore the schema
The first thing you need to do once your new empty cluster is ready is to restore the schema we captured earlier. You can do this by copying the schema file to one of your cassandra containers, then running the commands with cqlsh. Check the schema has been created once this has completed.

##### Copy the schema to cassandra-1
```docker cp schema.cql cassandra-1:/```

##### Restore it using CQLSH
```docker exec -it cassandra-1 cqlsh --file=/schema.cql```

#### Restore example data to the first node
Now you can restore the backup for the examples keyspace. We’ll use cassandra-1 for convenience.
* Copy the snapshot archive to cassandra-1
* Extract the archive into the /tmp directory (don’t restore it to the original location!)
* Prepare the files you want to restore
* Load those files into Cassandra

##### Copy the first snapshot to the "cassandra-1" container
```docker cp cassandra-1.snapshot.tar.gz cassandra-1:/```

##### Run an interactive bash shell in the "cassandra-1" container
```docker exec -it cassandra-1 bash```

##### Restore the snapshot
```
tar -zxvf /cassandra-1.snapshot.tar.gz -C /tmp
mkdir -p /tmp/restore/cassandra-1/examples
mv /tmp/var/lib/cassandra/data/examples/users-*/snapshots/exercise /tmp/restore/cassandra-1/examples/users
sstableloader -d 172.16.0.11 /tmp/restore/cassandra-1/examples/users
```

You should now be able to query data in the examples.users table, and you should also be able to see that the data has been distributed and replicated appropriately around the rest of the cluster nodes. Because every node had 100% of the data for this keyspace, we only have to restore one of the backups. Thanks “sstableloader”!

#### Restore the auto-generated data (“keyspace1”)
We’ll keep using cassandra-1 to load the backup data now, taking notice of how the data is distributed between the backup sets.

##### Run an interactive bash shell in the "cassandra-1" container
```docker exec -it cassandra-1 bash```

##### Restore the snapshot
```
mkdir -p /tmp/restore/cassandra-1/keyspace1
mv /tmp/var/lib/cassandra/data/keysp*/stand*/snapshots/exercise /tmp/restore/cassandra-1/keyspace1/standard1
sstableloader -d 172.16.0.11 /tmp/restore/cassandra-1/keyspace1/standard1
```

##### Check what’s been restored
Now you can use the illegal COUNT query again to see how many rows we have (since “keyspace1” only had 1 replica and we only restored 1 of the backups, it’s safe to assume we only have 1/3 of the data restored).
```SELECT COUNT(*) FROM keyspace1.standard1 LIMIT 100000;```

If you were to flush this keyspace on all 3 nodes you would find that the data is roughly evenly distributed. This is because your new cluster has a new random allocation of token ranges, and what used to belong entirely to cassandra-1 now belongs to all of the nodes.

#### Copy the rest of the backups
Now use the previous procedure to restore the rest of the data. The following example is for the cassandra-2 data, but you should run it again for the cassandra-3 data too.

##### Copy the snapshot to your container
```docker cp cassandra-2.snapshot.tar.gz cassandra-1:/```

##### Run an interactive bash shell in the "cassandra-1" container
```docker exec -it cassandra-1 bash```

##### Restore the snapshot
```
rm -rf /tmp/var
tar -zxvf /cassandra-2.snapshot.tar.gz -C /tmp
mkdir -p /tmp/restore/cassandra-2/keyspace1
mv /tmp/var/lib/cassandra/data/keysp*/stand*/snapshots/exercise /tmp/restore/cassandra-2/keyspace1/standard1
sstableloader -d 172.16.0.11 /tmp/restore/cassandra-2/keyspace1/standard1
```


Finishing up
------------
At this point you should have completely restored the data you backed up before destroying the cluster. Although this was done by hand (command by command), in practise the backup procedure should be scripted and scheduled with CRON.

Important things to remember:
* Backups are easy - just take the files from disk
* Snapshots can give us a point-in-time backup
* You can partially restore a dataset by choosing which sstables to load
* You can restore data to any node using the sstableloader command, which will re-distribute the restored data around the entire cluster
