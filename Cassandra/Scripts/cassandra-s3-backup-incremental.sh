#!/usr/bin/env bash
CASSANDRA_DATA_DIR='/media/ephemeral/cassandra/data'
DATE_STRING=`date +%F`
S3_SEVER_SIDE_ENCRYPTION_OPTIONS='<%= @backup_s3_sse_options %>'
S3_REGION='<%= @backup_s3_region %>'
S3_BACKUP_PATH_BASE='<%= @backup_s3_path_base %>'
S3_BACKUP_PATH="${S3_BACKUP_PATH_BASE}/${DATE_STRING}/${HOSTNAME}"

# Sync the data-directory to S3 (using server-side encryption):
echo "* Syncing backups (${CASSANDRA_DATA_DIR}/*/*/backups) to S3 (${S3_BACKUP_PATH}) ..."
/usr/local/bin/aws s3 sync --only-show-errors --size-only ${S3_SEVER_SIDE_ENCRYPTION_OPTIONS} --region=${S3_REGION} --exclude="*" --include="*/*/backups/*" ${CASSANDRA_DATA_DIR} ${S3_BACKUP_PATH}
