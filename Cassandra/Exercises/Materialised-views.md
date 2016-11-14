Exercise: Materialised views
============================


Overview
--------
In this exercise you will practise using materialised views to automatically maintain full secondary indices.


Pre-requisites
--------------
* A working single-node Cassandra cluster (assuming that the container is called "cassandra-1").

### Goals
* Create a simple schema to hold a list of drinks
* Create a materialised view to automatically index the drinks against their categories (as they're inserted)


### Run "cqlsh" in one of your Cassandra containers
```
docker exec -it <container-name/id> cqlsh -C
```


Background
----------

In previous exercises we've been through data-models requiring manual secondary indices, and discussed why native secondary indices aren't such a good idea. Of course there are issues with manual secondary indices too, so this exercise is designed to demonstrate a way to achieve exactly the same thing in a safer way using materialised views (__note the American spelling correction of "MaterialiZed view"__).


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
This CQL statement will create a new table called "drinks".
```
CREATE TABLE examples.drinks (
  drink_name varchar,
  category varchar,
  description varchar,
  rating int,
  PRIMARY KEY (drink_name)
);
```

#### Create a materialised view on this new table
This creates a materialised view to store drinks against their category.
```
CREATE MATERIALIZED VIEW examples.drinks_by_category AS
  SELECT *
  FROM examples.drinks
  WHERE category IS NOT NULL
  PRIMARY KEY (category, drink_name);
```

#### Insert test data
This will insert 5 drinks with 3 different categories (though in practise this can work on much large tables).
```
INSERT INTO examples.drinks (drink_name, category, description, rating) VALUES ('JagerMeister', 'booze', '23/24 hours of the day (nearly perfect)', 23);
INSERT INTO examples.drinks (drink_name, category, description, rating) VALUES ('Espresso', 'caffeine', '8/24 hours of the day (too jittery)', 8);
INSERT INTO examples.drinks (drink_name, category, description, rating) VALUES ('Earl Grey', 'caffeine', '16/24 hours of the day (pretty good)', 16);
INSERT INTO examples.drinks (drink_name, category, description, rating) VALUES ('Sierra Nevada', 'booze', '14/24 hours of the day (headache)', 14);
INSERT INTO examples.drinks (drink_name, category, description, rating) VALUES ('Water', 'thirst', '24/24 hours of the day (the original and best)', 24);
```


### Read the data back
You will now see that the data has been written twice.

#### The original table
The data was of course inserted into the `drinks` table.
```
SELECT * FROM examples.drinks WHERE drink_name = 'JagerMeister';
```

#### The materialised view
It was also stored in the materialised view
```
SELECT * FROM examples.drinks_by_category WHERE category = 'caffeine';
```


Finishing up
------------
As you can see, materialised views are a good way to avoid maintaining secondary indices "by hand", in a much safer way. Of course this will result in heavy disk and CPU usage on the cluster.
