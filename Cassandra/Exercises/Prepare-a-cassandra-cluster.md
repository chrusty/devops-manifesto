Exercise: Prepare a Cassandra cluster
=====================================


Overview
--------
In this exercise you will be building a Cassandra cluster in Docker containers on your laptop, go through some node-replacement / rebuild procedures, then shut it all down again.
Goals
* Understand how a cluster is assembled
* Learn how to query the cluster membership state
* Learn how to replace a node


Pre-requisites
--------------
* Docker installed on your machine
* Internet connectivity (for retrieving Docker images)


Useful Commands
---------------
### Get the logs from a container
`docker logs <container-name/id>`

### Run "nodetool status" in one of your Cassandra containers
`docker exec -it <container-name/id> nodetool status`

### Run "cqlsh" in one of your Cassandra containers
`docker exec -it <container-name/id> cqlsh`

### Run "bash" in one of your Cassandra containers
`docker exec -it <container-name/id> bash`


Steps
-----


### Build a 3-node cluster
This procedure will quickly get a 3-node Cassandra cluster up and running on your personal machine using Docker.


#### Create a network for your Cassandra containers
The first thing to do is to make a docker network specifically for Cassandra containers (so we can have some control over IP addressing).
`docker network create --subnet=172.16.0.0/24 cassandra`


#### Bring up a single-node cluster
Now you can bring up your first Cassandra node (172.16.0.11). This container will be called "cassandra-1".
`docker run --net=cassandra --ip=172.16.0.11 --name=cassandra-1 -d cassandra:3.7`


#### Check the status of your single-node cluster
Your new node will take a couple of seconds to come up. Check the docker logs for the container, and once it looks like it is running you can use nodetool to print out the cluster membership (at this stage you should only see one node). Any node with a "UN" status is UP and NORMAL.
`docker exec -it cassandra-1 nodetool status`


#### Introduce a second node
If your single-node cluster is running then you should now be able to introduce a second node. Again watch the logs to see how the node goes about joining, and use nodetool to check the cluster membership (note that you can do this on either of the nodes). Notice how we can pass configuration options to Cassandra with the Docker run command (in this case the [seed-list](https://docs.datastax.com/en/cassandra/2.1/cassandra/configuration/configCassandra_yaml_r.html#reference_ds_qfg_n1r_1k__seed_provider)). If you run "nodetool status" quick enough you may get to see the original node in "UN" status, and the new one in "UJ" (UP and JOINING) before they eventually both report "UN".

```docker run --net=cassandra --ip=172.16.0.12 --name=cassandra-2 -d -e CASSANDRA_SEEDS=172.16.0.11 cassandra:3.7```


#### Introduce a third node
If your two-node cluster looks good then you can proceed with adding a third node. Note that this time we’re using cassandra-2 as the seed. Since all nodes are peers, any active node can provide seed information.

```docker run --net=cassandra --ip=172.16.0.13 --name cassandra-3 -d -e CASSANDRA_SEEDS=172.16.0.12 cassandra:3.7```


### Temporarily take a node out of the cluster
This will show you how a Cassandra cluster managed nodes going offline and coming back.


#### Stop one of the nodes
Use the Docker stop command to bring cassandra-2 down, then use the nodetool status command on the remaining nodes to see what they think is going on. Also check the logs on the remaining machines and find any relevant messages.

```docker stop cassandra-2```


#### Start the node back up again
You can now use the docker start command to bring the cassandra-2 container back to life (its state will have been kept on disk and it should quickly come back up). Use the status command to show that its back, and again check the logs on the other nodes to see what they’ve said.

```docker start cassandra-2```

#### Consider the implications of a node temporarily going offline
Cassandra is designed to gracefully handle nodes temporarily going offline (this is how we would do scheduled maintenance and deal with hardware failures/replacements in the real world). There are however some implications to consider:
* [What would happen to queries using consistency-level "ALL" during this time?](https://docs.datastax.com/en/cassandra/2.1/cassandra/dml/dml_config_consistency_c.html)
* [What happens to the data that should have replicated to the node that was down during this time?](https://docs.datastax.com/en/cassandra/2.1/cassandra/dml/dml_about_hh_c.html?hl=hinted,handoff)
* [How can we ensure that data is consistent after an event such as this?](https://docs.datastax.com/en/cassandra/2.1/cassandra/operations/opsRepairNodesManualRepair.html?hl=repair)
* [Is there a less-invasive way to fix this data?](https://docs.datastax.com/en/cassandra/2.1/cassandra/operations/opsRepairNodesReadRepair.html?hl=repair)


### Completely replace a node in the cluster
We will simulate a complete hardware failure of one of the cluster nodes, and replace it with a new one.


#### Stop a node and delete the container
Let’s pick on cassandra-2 again. The following commands will stop the container and delete it from Docker. Once that is done use nodetool to display the cluster status.

```
docker stop cassandra-2
docker rm cassandra-2
```

#### Attempt to bring up a replacement
The same command we originally used to bring up cassandra-2 can be used again. Don’t wait too long for it to join though, because it won’t actually succeed! Check the logs for the new cassandra-2 container to find out why.

```docker run --net=cassandra --ip=172.16.0.12 --name=cassandra-2 -d -e CASSANDRA_SEEDS=172.16.0.11 cassandra:3.7```


#### Attempt to bring up an additional node instead
If we can’t introduce cassandra-2 again with the same IP address as before, surely we could just choose to bring in Cassandra-4 instead? No, this won’t work either. Check the logs to find out why.

```docker run --net=cassandra --ip=172.16.0.14 --name cassandra-4 -d -e CASSANDRA_SEEDS=172.16.0.11 cassandra:3.7```


#### Assassinate the dead node from the cluster
One way to handle this scenario is to "assassinate" the dead node from the cluster before attempting to introduce a replacement node. This is potentially ___danger-zone___! Run this command on one of the remaining nodes. It will take about 30s, check the logs afterwards to see what happened. Nodetool status should now say that you have 2 nodes in "UN" state, and nothing else.

```docker exec -it cassandra-1 nodetool assassinate 172.16.0.12```


#### Cleanup then bring up a replacement
The cluster is now ready for a replacement node to join (after cleaning up some junk first).

##### Delete cassandra-2 and cassandra-4

```docker rm cassandra-2 cassandra-4```

##### Start a new cassandra-2

```docker run --net=cassandra --ip=172.16.0.12 --name=cassandra-2 -d -e CASSANDRA_SEEDS=172.16.0.11 cassandra:3.7```


#### Run a repair to make sure your data is still consistent
If this cluster had any data in it then we will have of course lost some when we killed cassandra-2. This is why for all but the least important datasets we would always maintain multiple replicas (usually 3). This would allow us to "repair" the data in the cluster by streaming replicas to the new node from its neighbours until we have the desired number of copies again. Try this command on one of the nodes in your cluster.

```docker exec -it cassandra-1 nodetool repair```


Finishing up
------------
At this point you should have a healthy 3-node cluster again. This exercise was only concerned with cluster membership and node replacement (no data-verification was performed). In the future you may want to try this exercise again on a cluster with some actual data (once you’re happy with creating schemas / replication topologies / inserting).


You can now simply stop and remove the Cassandra containers if you don’t want them any more, then finally remove the network we created at the beginning.

```
docker stop cassandra-1 cassandra-2 cassandra-3
docker rm cassandra-1 cassandra-2 cassandra-3
docker network rm cassandra
```
