Exercise: Auto expiring data with TTL
=====================================


Overview
--------
In this exercise you will practise using Cassanda's TTL (Time-To-Live) feature.


Pre-requisites
--------------
* A working single-node Cassandra cluster (assuming that the container is called "cassandra-1").

### Goals
* Expire data using the default TTL for a table
* Expire data using specific TTLs on insert


### Run "cqlsh" in one of your Cassandra containers
```
docker exec -it <container-name/id> cqlsh -C
```


Steps
-----


### Prepare a simple schema
We’ll use a very simple one-to-one table as an example schema. Schema-definition and data-manipulation is done through the "cqlsh" utility (the command to run this is listed above).


#### Create a keyspace
This CQL statement will create a new keyspace called "examples" using the simple replication-strategy with one replica.
```
CREATE KEYSPACE IF NOT EXISTS examples WITH replication = {'class': 'SimpleStrategy', 'replication_factor': '1'};
```


### Default TTL
You will now insert some test data and see it expire using the default TTL. Again, the CQL statements are run in "cqlsh".

#### Create a "temporary-access" table
This CQL statement will create a new table called "temporary_access", holding access tokens which expire after 60s using a default TTL for the table.
```
CREATE TABLE examples.temporary_access (
  access_token varchar,
  insert_time timestamp,
  PRIMARY KEY (access_token)
) WITH DEFAULT_TIME_TO_LIVE = 60;
```

#### Insert test data
```
INSERT INTO examples.temporary_access (access_token, insert_time) VALUES ('token1', toTimestamp(now()));
```

#### Wait 10s then insert some more
```
INSERT INTO examples.temporary_access (access_token, insert_time) VALUES ('token2', toTimestamp(now()));
```

#### Query the data to prove that it is there
Query the data before the first record expires, then keep querying it until you see them fall out of the result set. Note that we can query the TTL for columns:
```
SELECT access_token, insert_time, TTL(insert_time) FROM examples.temporary_access;
```


### Arbitrary TTL
You will now insert some test data and see it expire using arbitrary TTLs. Again, the CQL statements are run in "cqlsh".

#### Create a "banned-users" table
This CQL statement will create a new table called "banned_users", which will hold a list of banned users. Bans will expire after an arbitrary amount of time (defined when we insert data).
```
CREATE TABLE examples.banned_users (
  user_name varchar,
  insert_time timestamp,
  ban_reason varchar,
  ban_duration varchar,
  PRIMARY KEY (user_name)
);
```

#### Insert test data
```
INSERT INTO examples.banned_users (user_name, insert_time, ban_reason, ban_duration) VALUES ('chris', toTimestamp(now()), 'being a douche', '5 minutes') USING TTL 300;
INSERT INTO examples.banned_users (user_name, insert_time, ban_reason, ban_duration) VALUES ('james', toTimestamp(now()), 'swearing', '1 minute') USING TTL 60;
INSERT INTO examples.banned_users (user_name, insert_time, ban_reason, ban_duration) VALUES ('isaac', toTimestamp(now()), 'abusive language', '2 minutes') USING TTL 120;
```

#### Query the data to prove that it is there
Query the data before the first record expires, then keep querying it until you see them fall out of the result set.
```
SELECT user_name, insert_time, ban_reason, ban_duration, TTL(ban_reason) FROM examples.banned_users;
```

#### Use a TTL for a specific column (not an entire "row")
You can even apply TTLs to individual columns. In this instance we'll set a TTL on the "ban_reason" column for the banned user called "chris" (as long as 5 minutes hasn't elapsed since you inserted that user). After 10s you should see the ban_reason column become NULL.
```
INSERT INTO examples.banned_users (user_name, ban_reason) VALUES ('chris', 'not such a douche after all') USING TTL 10;
```

Finishing up
------------
You have just witnessed how data can be automatically aged-out of Cassandra. Bear in mind that data isn't actually removed once the TTL has expired... it is simply omitted from query results. It will in fact live on-disk for the duration of the grace-period, then removed during a compaction or repair after that time has elapsed.
