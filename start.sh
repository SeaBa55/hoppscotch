#!/bin/sh

# Start PostgreSQL
su - postgres -c "pg_ctl start -D /var/lib/postgresql/data -l /var/lib/postgresql/logfile"

# Wait for PostgreSQL to start
sleep 10

# Create the database
su - postgres -c "createdb hoppscotch"

# Wait for PostgreSQL to start
sleep 10

# Start your application
node /usr/src/app/aio_run.mjs

