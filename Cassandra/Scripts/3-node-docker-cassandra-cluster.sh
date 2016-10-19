#!/usr/bin/env bash

if [ "$1" == "stop" ]
then
	echo "Stopping Cassandra containers ..."
	docker stop cassandra-1 cassandra-2 cassandra-3

	echo "Removing Cassandra containers ..."
	docker rm cassandra-1 cassandra-2 cassandra-3

	echo "Removing Cassandra network ..."
	docker network rm cassandra
else
	echo "Creating a virtual Docker network for Cassandra ..."
	docker network create --subnet=172.16.0.0/24 cassandra

	echo "Creating the first Cassandra instance (cassandra-1) ..."
	docker run --net=cassandra --ip=172.16.0.11 --name=cassandra-1 -d cassandra:3.7

	echo "Waiting 10s ..."
	sleep 10

	echo "Creating the second Cassandra instance (cassandra-2) ..."
	docker run --net=cassandra --ip=172.16.0.12 --name=cassandra-2 -d -e CASSANDRA_SEEDS=172.16.0.11 cassandra:3.7

	echo "Waiting 90s ..."
	sleep 90

	echo "Creating the third Cassandra instance (cassandra-3) ..."
	docker run --net=cassandra --ip=172.16.0.13 --name cassandra-3 -d -e CASSANDRA_SEEDS=172.16.0.11 cassandra:3.7

	echo "Listing the running containers ..."
	docker ps |grep cassandra
fi
