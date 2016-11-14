Exercise: Copying tables
========================


Overview
--------
In this exercise you will practise using Cassanda's COPY feature, which allows you to dump an entire table to disk and re-load it again.


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


Steps
-----


### Prepare a simple schema
We’ll use a very simple one-to-one table as an example schema. Schema-definition and data-manipulation is done through the "cqlsh" utility (the command to run this is listed above).


#### Create a keyspace
This CQL statement will create a new keyspace called "examples" using the simple replication-strategy with one replica.
```
CREATE KEYSPACE IF NOT EXISTS examples WITH replication = {'class': 'SimpleStrategy', 'replication_factor': '1'};
```

#### Create a table to hold some test data
This CQL statement will create a new table called "playlists", holding 
```
CREATE TABLE examples.playlists (
  playlist_name varchar,
  song_title varchar,
  duration int,
  artist_name varchar,
  PRIMARY KEY (playlist_name, song_title)
);
```

#### Insert test data
This will insert 5 songs into 3 playlists (though in practise this can work on much large tables).
```
INSERT INTO examples.playlists (playlist_name, song_title, duration, artist_name) VALUES ('Smooth', 'The Art of Easing', 305, 'Digable Planets');
INSERT INTO examples.playlists (playlist_name, song_title, duration, artist_name) VALUES ('Smooth', 'Re Run Home', 845, 'Kamasi Washington');
INSERT INTO examples.playlists (playlist_name, song_title, duration, artist_name) VALUES ('Rough', 'The Pot', 381, 'Tool');
INSERT INTO examples.playlists (playlist_name, song_title, duration, artist_name) VALUES ('Rough', 'Ratamahatta', 270, 'Sepultura');
INSERT INTO examples.playlists (playlist_name, song_title, duration, artist_name) VALUES ('Weird', 'The Air-Conditioned Nightmare', 845, 'Mr Bungle');
```


### Dump the table to a CSV file on disk
The following command will dump the contents of the playlists table to disk.
```
COPY playlists to '/playlists.csv';
```


### Restore the CSV file into a new table
We'll now create a new table and load the data back into it.

#### Prepare a new table
```
CREATE TABLE examples.playlists_backup (
  playlist_name varchar,
  song_title varchar,
  duration int,
  artist_name varchar,
  PRIMARY KEY (playlist_name, song_title)
);
```

#### Copy the CSV data back into it:
```
COPY playlists_backup FROM '/playlists.csv';
```


Finishing up
------------
This is a very simple demo, because the process itself is very simple. This can be a useful way to share datasets or to make quick backups and restores.

Beware that on large tables this will of course become quite a heavy operation (heavy enough to cause the rest of your queries to timeout while its running).
