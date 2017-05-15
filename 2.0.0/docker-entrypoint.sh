#!/bin/bash
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy of
# the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.

set -e

if [ "$1" = '/opt/couchdb/bin/couchdb' ]; then
	# we need to set the permissions here because docker mounts volumes as root
	chown -R couchdb:couchdb /opt/couchdb

	chmod -R 0770 /opt/couchdb/data

	chmod 664 /opt/couchdb/etc/*.ini
	chmod 664 /opt/couchdb/etc/local.d/*.ini
	chmod 775 /opt/couchdb/etc/*.d

	if [ "$COUCHDB_SYNC_ADMINS_NODE" ]; then
		# Wait until the node is ready and then retrieve the hashed password. As per
		# https://github.com/apache/couchdb-docker/issues/9#issuecomment-301363800 need to use same
		# hashed password across all nodes so that session cookies can be reused.
		COUCHDB_HASHED_PASSWORD=`/usr/src/wait-for-it.sh $COUCHDB_SYNC_ADMINS_NODE:5984 -t 300 -- curl http://$COUCHDB_USER:$COUCHDB_PASSWORD@$COUCHDB_SYNC_ADMINS_NODE:5984/_node/couchdb@$COUCHDB_SYNC_ADMINS_NODE/_config/admins/$COUCHDB_USER | sed "s/^\([\"]\)\(.*\)\1\$/\2/g"`
	fi

	# Use sname so that we can specify a short name, like those used by docker, instead of a host
	if [ ! -z "$NODENAME" ] && ! grep "couchdb@" /opt/couchdb/etc/vm.args; then
		# Cookie is needed so that the nodes can connect to each other using Erlang clustering
		if [ -z "$COUCHDB_COOKIE" ]; then
			echo "-sname couchdb@$NODENAME" >> /opt/couchdb/etc/vm.args
		else
			echo "-sname couchdb@$NODENAME -setcookie '$COUCHDB_COOKIE'" >> /opt/couchdb/etc/vm.args
		fi
	fi

	if [ "$COUCHDB_USER" ] && [ "$COUCHDB_PASSWORD" ] && [ -z "$COUCHDB_SYNC_ADMINS_NODE" ]; then
		# Create admin
		printf "[admins]\n%s = %s\n" "$COUCHDB_USER" "$COUCHDB_PASSWORD" > /opt/couchdb/etc/local.d/docker.ini
		chown couchdb:couchdb /opt/couchdb/etc/local.d/docker.ini
	fi

	if [ "$COUCHDB_USER" ] && [ "$COUCHDB_HASHED_PASSWORD" ]; then
		printf "[admins]\n%s = %s\n" "$COUCHDB_USER" "$COUCHDB_HASHED_PASSWORD" > /opt/couchdb/etc/local.d/docker.ini
		chown couchdb:couchdb /opt/couchdb/etc/local.d/docker.ini
	fi

	if [ "$COUCHDB_SECRET" ]; then
		# Set secret
		printf "[couch_httpd_auth]\nsecret = %s\n" "$COUCHDB_SECRET" > /opt/couchdb/etc/local.d/secret.ini
		chown couchdb:couchdb /opt/couchdb/etc/local.d/secret.ini
	fi

	# if we don't find an [admins] section followed by a non-comment, display a warning
	if ! grep -Pzoqr '\[admins\]\n[^;]\w+' /opt/couchdb/etc/local.d/*.ini; then
		# The - option suppresses leading tabs but *not* spaces. :)
		cat >&2 <<-'EOWARN'
			****************************************************
			WARNING: CouchDB is running in Admin Party mode.
			         This will allow anyone with access to the
			         CouchDB port to access your database. In
			         Docker's default configuration, this is
			         effectively any other container on the same
			         system.
			         Use "-e COUCHDB_USER=admin -e COUCHDB_PASSWORD=password"
			         to set it in "docker run".
			****************************************************
		EOWARN
	fi


	exec gosu couchdb "$@"
fi

exec "$@"
