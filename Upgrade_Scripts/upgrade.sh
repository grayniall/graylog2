#!/bin/bash
#Provided by @mrlesmithjr
#EveryThingShouldBeVirtual.com

set -e
# Setup logging
# Logs stderr and stdout to separate files.
exec 2> >(tee "./graylog2/install_graylog2.err")
exec > >(tee "./graylog2/install_graylog2.log")

GRAYLOGSERVER_VERSION="graylog-1.1.2"
GRAYLOGSERVER_FILE="$GRAYLOGSERVER_VERSION.tgz"
GRAYLOGWEB_VERSION="graylog-web-interface-1.1.2"
GRAYLOGWEB_FILE="$GRAYLOGWEB_VERSION.tgz"

DOWNLOAD_DIRECTORY="/opt"
GRAYLOG_CONFIG_FILE="/etc/graylog.conf"
GRAYLOG_WEB_CONFIG_FILE="/opt/graylog2-web-interface/conf/graylog-web-interface.conf"

# Setup Pause function
function pause(){
   read -p "$*"
}

function DownloadAndExtract() {
	echo $1
	wget -q -P "$DOWNLOAD_DIRECTORY" $1
	
	if [ ! -z "$2" ]
	then
		tar zxf "$DOWNLOAD_DIRECTORY/$2" -C "$DOWNLOAD_DIRECTORY"
		mv "$DOWNLOAD_DIRECTORY/$3" "$DOWNLOAD_DIRECTORY/$4"
	fi	
	echo "Done"
}

function GetIPAddress() {
	echo "Detecting IP Address"
	IPADDY="$(ifconfig | grep -A 1 'eth1' | tail -1 | cut -d ':' -f 2 | cut -d ' ' -f 1)"
	echo "Detected IP Address is $IPADDY"

	SERVERNAME=$IPADDY
	SERVERALIAS=$IPADDY
}

GetIPAddress

# Save existing config file
sudo cp /opt/graylog2-web-interface/conf/graylog-web-interface.conf ~/graylog-web-interface.conf

rm -rf /opt/graylog2-server*
rm -rf /opt/graylog2-web-interface*
rm -f /opt/graylog2-server*.*gz
rm -f /opt/graylog2-web-interface*.*gz

# Download Elasticsearch, Graylog2-Server and Graylog2-Web-Interface
DownloadAndExtract https://packages.graylog2.org/releases/graylog2-server/$GRAYLOGSERVER_FILE $GRAYLOGSERVER_FILE $GRAYLOGSERVER_VERSION "graylog2-server"
DownloadAndExtract https://packages.graylog2.org/releases/graylog2-web-interface/$GRAYLOGWEB_FILE $GRAYLOGWEB_FILE $GRAYLOGWEB_VERSION "graylog2-web-interface"

sudo sed -i -e 's|GRAYLOG_CONF=${GRAYLOG_CONF:=/etc/graylog/server/server.conf}|GRAYLOG_CONF=${GRAYLOG_CONF:=/etc/graylog.conf}|' /opt/graylog2-server/bin/graylogctl

service graylog2-server start

# Waiting for Graylog2-Server to start accepting requests on tcp/12900
echo "Waiting for Graylog2-Server to start!"
while ! nc -vz localhost 12900; do sleep 1; done

# Fixing /opt/graylog2-web-interface Permissions
echo "Fixing Graylog2 Web Interface Permissions"
chown -R root:root /opt/graylog2*

# Cleaning up /opt
echo "Cleaning up"
rm $DOWNLOAD_DIRECTORY/*tgz -f
rm $DOWNLOAD_DIRECTORY/*deb -f

# Restart All Services
echo "Restarting All Services Required for Graylog2 to work"
service elasticsearch restart
service mongod restart
service rsyslog restart

sudo cp ~/graylog-web-interface.conf /opt/graylog2-web-interface/conf/graylog-web-interface.conf
echo "Starting graylog2-web-interface"
service graylog2-web-interface start

# All Done
echo "Upgrade has completed!!"
echo "Browse to IP address of this Graylog2 Server Used for Installation"
echo "Browse to http://$SERVERNAME:9000 If Different"
echo "EveryThingShouldBeVirtual.com"
echo "@mrlesmithjr"
