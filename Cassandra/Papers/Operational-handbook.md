Cassandra: Operational handbook
===============================


Introduction
------------
This document is intended to provide a list of useful procedures and approaches for the type of day-to-day operational activities required to keep a Cassandra cluster up and running.


Upgrades
--------
Cassandra is an active open-source project... new features and bug-fixes are released regularly, and although an attempt is made to port new features up and down between branches, the reality is that the focus of attention is on the newest versions of the codebase.

### Reasons to upgrade
* Bug-fixes
* New features
* Performance enhancements
* Security fixes
* Supportability (most of the churn in the forums is related to recent versions, and if something is broken they’d rather tell you to upgrade first before trying to fix an old version)
* Hiring (anyone new to Cassandra will have learned on recent versions)
* Compatibility with new client libraries

### Reasons NOT to upgrade
* Stability (if it ain’t broken then why risk changing things)
* Newer features haven’t been tested as much
* Newer features are more likely to have breaking changes applied soon
* Compatibility with legacy client libraries (if you’re stuck on something old)

### Upgrade policy
Taking the last two lists of points into account, the upgrade policy I’ve taken in the past is something like this:
* Run the latest minor version of the second-to-latest major branch
* Upgrade minor versions for bugfixes if they are encountered
* Upgrade the major version as soon as you’re no longer on the second-to-latest

### Rolling upgrades
The Cassandra developers make a point of allowing backwards-interoperability between 1 major versions difference (eg 2.2 will work with 2.1, 2.1 will work with 2.0). This allows you to upgrade a Cassandra cluster online, without causing an outage. The procedure is as follows:
* Prevent repairs and backups from running for the duration of the upgrade.
* Drain the first node (```nodetool drain```), then stop Cassandra on it.
* Upgrade the Cassandra code (package or container, as long as you can keep the data directories between versions).
* Start Cassandra, and watch it join back into the cluster.
* Upgrade the SSTable files (```nodetool upgradesstables```).
* Move on to the next node and do the same thing again, until they’re all done.


At any time you can use the ```nodetool gossipinfo``` command to display the version of Cassandra running on each node in the cluster. You should aim to get the rolling-upgrade done as quickly as possible, as the background streaming tasks like hints and repairs are not guaranteed to work during this time.


Backups & Restores
------------------
Backing up Cassandra is relatively easy, given that you can just take the files from disk (without having to run lengthy dump commands or take the service offline). There are some patterns which can help get this right.

Unfortunately it takes time to restore data to Cassandra, and it is almost impossible to do it at anything other than table-at-a-time. So I hope for your sake that you don’t have to do this in an emergency situation. Personally I have done a lot of restores, but it is usually because I’m trying to build a NEW cluster for testing purposes, and want to populate them with a known dataset.

### Snapshots
Use the ```nodetool snapshot``` command to create an instant point-in-time snapshot on disk. This just creates a directory for each table full of symbolic links. You can then copy them off the Cassandra instances at your leisure.

#### Warning
Although snapshots themselves don’t use any extra space, if you have a high compaction workload (updates or deletes) then this will cause new sstables to be created for your working set which effectively duplicate your snapshot data. For this reason you should clear snapshots (```nodetool clearsnapshot```) once you’ve used them.


### Backups
This section is all about backups. It normally involves CRON, shell-scripts, shared-storage, and lots of network bandwidth.

#### Define your backup policy
* Do you want to be able to restore to a given point-in-time?
* If so, what is the granularity (to an hour, to a day, to a week etc).
* If so, how long do you want to keep old backups for?

#### Schedule
I usually schedule backup jobs through CRON. I prefer to randomise the schedules to spread the workload over as much time as possible (pretty pointless to have 100 nodes all run their backups at midnight just because you’re too lazy to do this another way).

#### Script
You should turn your backup job into a shell script to perform the following actions:
* Create a named snapshot (this will flush the data to disk and give you a quiet backup target).
* Use the "find" command to create a list of the files you want to backup (allows you to just look for the snapshot directories, and ignore the rest of the stuff).
* Use something like "rsync" or the "aws" command to copy these files somewhere offline (using the list).
* If you only want the latest snapshot then use the ```--delete``` flag, otherwise copy the data into a folder that includes the cluster-name, the host-name, year/month/day, and a timestamp.
* Clear the snapshot (remember they can cause data-divergence and start using space).
Storage
Something like S3 is an ideal place to host your backups, because it supports TTLs (you can mark each file with an expiration time). This way you can age your old backups out of storage. You can also use retention-policies to archive certain data to long-term cheap storage (Glacier).

If you aren’t able to use S3 and retention-policies then you’ll need to make sure that you clean up after yourself.


### Restores
Restoring data is quite simple too, and generally follows this procedure:
* Create the schemas you need for the tables being restored.
* Identify which files you need to restore.
* Copy them to a node in your Cassandra cluster.
* Move the files you want into a directory called "___<keyspace>/<table>___" (the next command requires this).
* Use the ```sstableloader``` command to load the data you want to restore. It will distribute it around your cluster, and ensure that you end up with the correct number of replicas.


Emergencies
-----------
Hopefully you will make it through your life without ever having to deal with an emergency in a distributed-database (known in some circles as a "_cluster-f&^k_"). You can generally avoid this by heeding this advice:
* Run all code-changes through dev / staging / load-test BEFORE running them in production.
* Load-test all code-changes BEFORE running them in production.
* Move slowly - don’t make more than one change at a time.
* If you EVER hit anything that you can’t find an explanation for, STOP and research it. Sometimes the warning signs are subtle.

### Disk filling up
Ideally you would never allow a Cassandra node to run out of disk-space. If your cluster starts filling up then you need to add more nodes in a controlled manner. I would usually start thinking about this when the data-volume hits 50%, and execute the plan by the time it hits 60%. 100% is too late - by this point you couldn’t actually add more nodes to take pressure away from this one (even if the Cassandra process hadn’t crashed). This is because Cassandra needs to compact data before it can stream it to the new nodes, and compactions require more space temporarily.

#### Plan A: Kill the node
Hopefully you had more than one replica of your data in this cluster? In that case you could just kill this node and re-introduce one with more storage. Once this new node is in, add more.
* Check that the Cassandra process is stopped on the full node.
* Run ```nodetool assassinate <dead-nodes-ip-address>``` on one of the remaining nodes.
* Introduce a new node with more storage.
* Run a repair just to make sure.
* Now you need to either replace the other nodes so they have the same amount of storage, and / or introduce some new nodes.

#### Plan B: Increase the storage on the node
* Mount a new volume to the node
* Copy the data to the new volume
* Unmount the old volume, mount the new one in-place
* Re-start Cassandra


### Rolling-restart
If you want to push a configuration change to all of the nodes, it is possible to restart each node one-at-a-time, wait for it to fully come back into the cluster, then move on with the next one. This procedure will not cause an outage (as long as your client libraries handle re-tries).

### The "Nuclear Option"
It is good to have a powerful red-button at hand in case everything really turns bad. However, the situation must be quite bad before you should consider this. Effectively, the "nuclear option" involves restarting Cassandra on all of the nodes in the cluster simultaneously. This will of course cause an outage, but any background task will have been killed and the cluster will reset back to a quiescent state.

#### Repair is killing the cluster
Sometimes this is caused by a repair. Realistically your cluster needs to be sufficiently specced to be able to not only serve your live traffic, but also handle repairs in the background. Repairs are necessary, and under NO circumstances should you ever consider "disabling repairs" because of their performance implications. Instead this suggests that your nodes don’t have enough power (probably disk I/O) to handle the workload.

The bottom line is that while restarting your cluster will stop the repair, you will probably have issues again the next time it happens (unless the repair just happened to coincide with your daily / weekly / monthly / yearly peak).

One potential solution is to switch to sequential repairs instead of parallel - less of the cluster will be involved (but it will also take much longer to complete).


#### Compactions are killing the cluster
At other times you may need to restart nodes because compactions have ground your performance to a crawl. As with repairs, compactions are necessary and if your cluster can’t keep up then you will have to either modify the write patterns, throw more I/O at the storage systems, or scale the cluster out until each node is holding less data than it was before (therefore serving less queries, writing less data, and having to compact less).


#### Garbage collection is killing the cluster
If you find that garbage-collection is getting worse and worse over time before requiring you to restart nodes, again a rolling-restart will temporarily fix your issues, but you may need to make some modifications to prevent it from happening again.


Slow garbage-collection can indicate that you haven’t allocated enough CPU power (cores) to your nodes. The JVM will attempt to collect as much garbage as it can within time limits. Anything it can’t get to is left for later. If this is always the case, eventually the JVM will run out of heap space and have to do more frequent collections over an ever-diminishing pool of memory.

In this circumstance it can be beneficial to trigger regular manual garbage collections through a JMX client and CRON.


### Dead node
From time to time a hardware failure will take one of your nodes offline. If it is impossible to get it back then you will need to replace it, following this procedure:
* From one of the nodes that is still up, run ```nodetool assassinate <ip-address-of-dead-node>```
* Join a replacement node to the cluster
* Run a full repair
