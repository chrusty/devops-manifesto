#!/usr/bin/env bash
CASSANDRA_DATA_DIR='/var/lib/cassandra/data'
DATE_STRING=`date +%F`
S3_SEVER_SIDE_ENCRYPTION_OPTIONS=''
S3_REGION='eu-west-1'
S3_BACKUP_PATH_BASE='s3://backups/Cassandra/cruft-cluster'
S3_BACKUP_PATH="${S3_BACKUP_PATH_BASE}/${DATE_STRING}/${HOSTNAME}"
CASSANDRA_SNAPSHOT_NAME=`date +%s`
CLEAR_SNAPSHOT=true
INCREMENTAL_BACKUPS_ENABLED=false

# Dump the schema:
echo "* Dumping schema ..."
echo 'desc schema;' |cqlsh 1>/tmp/cassandra-schema.cql

# Dump the cluster-membership:
echo "* Dumping cluster-membership ..."
nodetool ring 1>/tmp/cassandra-ring.txt

# Copy the metadata to S3:
echo "* Copying metadata to S3 (${S3_BACKUP_PATH}) ..."
/usr/local/bin/aws s3 cp --only-show-errors ${S3_SEVER_SIDE_ENCRYPTION_OPTIONS} --region=${S3_REGION} /tmp/cassandra-schema.cql ${S3_BACKUP_PATH}/
/usr/local/bin/aws s3 cp --only-show-errors ${S3_SEVER_SIDE_ENCRYPTION_OPTIONS} --region=${S3_REGION} /tmp/cassandra-ring.txt ${S3_BACKUP_PATH}/

# Removing previous incremental backups:
echo "* Removing previous incremental backups ..."
find ${CASSANDRA_DATA_DIR}/*/*/backups/ -type f -delete

# Ensure that incremental-backups are enabled (if that's what we want):
if [ ${INCREMENTAL_BACKUPS_ENABLED} ]
then
	echo "* Enabling incremental backups ..."
	nodetool enablebackup
else
	echo "* Disabling incremental backups ..."
	nodetool disablebackup
fi

# Make a snapshot:
echo "* Creating snapshot \"${CASSANDRA_SNAPSHOT_NAME}\" ..."
nodetool snapshot -t ${CASSANDRA_SNAPSHOT_NAME} 1>/dev/null

# Sync the data-directory to S3 (using server-side encryption):
echo "* Syncing snapshot (${CASSANDRA_DATA_DIR}/*/*/snapshots/${CASSANDRA_SNAPSHOT_NAME}) to S3 (${S3_BACKUP_PATH}) ..."
/usr/local/bin/aws s3 sync --only-show-errors --size-only ${S3_SEVER_SIDE_ENCRYPTION_OPTIONS} --region=${S3_REGION} --exclude="*" --include="*/*/snapshots/${CASSANDRA_SNAPSHOT_NAME}/*" ${CASSANDRA_DATA_DIR} ${S3_BACKUP_PATH}

# Clear the snapshot:
if [ ${CLEAR_SNAPSHOT} ]
then
    echo "* Clearing snapshot \"${CASSANDRA_SNAPSHOT_NAME}\" ..."
    nodetool clearsnapshot ${CASSANDRA_SNAPSHOT_NAME} 1>/dev/null
else
    echo "* Not clearing snapshot \"${CASSANDRA_SNAPSHOT_NAME}\"."
fi
