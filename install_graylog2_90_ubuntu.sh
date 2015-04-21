#!/bin/bash
#Provided by @mrlesmithjr
#EveryThingShouldBeVirtual.com

set -e
# Setup logging
# Logs stderr and stdout to separate files.
exec 2> >(tee "./graylog2/install_graylog2.err")
exec > >(tee "./graylog2/install_graylog2.log")

ELASTICSEARCH_VERSION="elasticsearch-1.5.0.deb"
MONGODB_VERSION=""

GRAYLOGSERVER_VERSION="graylog-1.0.1"
GRAYLOGSERVER_FILE="$GRAYLOGSERVER_VERSION.tgz"
GRAYLOGWEB_VERSION="graylog-web-interface-1.0.1"
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

function InstallPreReqs() {
	echo "Disabling CD Sources and Updating Apt Packages and Installing Pre-Reqs"
	sed -i -e 's|deb cdrom:|# deb cdrom:|' /etc/apt/sources.list
	
	apt-get -qq update
	apt-get -y install git curl build-essential openjdk-7-jre pwgen wget netcat
}

function GetIPAddress() {
	echo "Detecting IP Address"
	IPADDY="$(ifconfig | grep -A 1 'eth1' | tail -1 | cut -d ':' -f 2 | cut -d ' ' -f 1)"
	echo "Detected IP Address is $IPADDY"

	SERVERNAME=$IPADDY
	SERVERALIAS=$IPADDY
}

GetIPAddress
InstallPreReqs

# Download Elasticsearch, Graylog2-Server and Graylog2-Web-Interface
echo "Downloading Elastic Search, Graylog2-Server and Graylog2-Web-Interface to /opt"
DownloadAndExtract https://download.elasticsearch.org/elasticsearch/elasticsearch/elasticsearch-1.5.0.deb
DownloadAndExtract https://packages.graylog2.org/releases/graylog2-server/$GRAYLOGSERVER_FILE $GRAYLOGSERVER_FILE $GRAYLOGSERVER_VERSION "graylog2-server"
DownloadAndExtract https://packages.graylog2.org/releases/graylog2-web-interface/$GRAYLOGWEB_FILE $GRAYLOGWEB_FILE $GRAYLOGWEB_VERSION "graylog2-web-interface"

# Create Symbolic Links
#echo "Creating SymLink Graylog2-server"
#ln -s $DOWNLOAD_DIRECTORY/graylog2-server/ /opt/graylog2-server

# Install elasticsearch
echo "Installing elasticsearch"
dpkg -i $DOWNLOAD_DIRECTORY/$ELASTICSEARCH_VERSION
sed -i -e 's|#cluster.name: elasticsearch|cluster.name: graylog2|' /etc/elasticsearch/elasticsearch.yml

# Making elasticsearch start on boot
sudo update-rc.d elasticsearch defaults 95 10

# Restart elasticsearch
service elasticsearch restart

# Test elasticsearch
# curl -XGET 'http://localhost:9200/_cluster/health?pretty=true'

# Install mongodb
echo "Installing MongoDB"
apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 7F0CEB10
echo "deb http://downloads-distro.mongodb.org/repo/ubuntu-upstart dist 10gen" | tee /etc/apt/sources.list.d/10gen.list
apt-get -qq update
apt-get -y install mongodb-10gen

# Waiting for MongoDB to start accepting connections on tcp/27017
echo "!!!*** Waiting for MongoDB to start accepting connections ***!!!"
echo "This could take a while so connection timeouts below are normal!"
while ! nc -vz localhost 27017; do sleep 1; done

# Making changes to /etc/security/limits.conf to allow more open files for elasticsearch
mv /etc/security/limits.conf /etc/security/limits.bak
grep -Ev "# End of file" /etc/security/limits.bak > /etc/security/limits.conf
echo "elasticsearch soft nofile 32000" >> /etc/security/limits.conf
echo "elasticsearch hard nofile 32000" >> /etc/security/limits.conf
echo "# End of file" >> /etc/security/limits.conf

# Install graylog2-server

#adminpass=

cp $DOWNLOAD_DIRECTORY/graylog2-server/graylog.conf{.example,}
mv $DOWNLOAD_DIRECTORY/graylog2-server/graylog.conf $GRAYLOG_CONFIG_FILE
#ln -s /opt/graylog2-server/graylog2.conf $GRAYLOG_CONFIG_FILE
pass_secret=$(pwgen -s 96)
sed -i -e 's|password_secret =|password_secret = '$pass_secret'|' $GRAYLOG_CONFIG_FILE
#root_pass_sha2=$(echo -n password123 | shasum -a 256)
admin_pass_hash=$(echo -n $adminpass|sha256sum|awk '{print $1}')
sed -i -e "s|root_password_sha2 =|root_password_sha2 = $admin_pass_hash|" $GRAYLOG_CONFIG_FILE
sed -i -e 's|elasticsearch_shards = 4|elasticsearch_shards = 1|' $GRAYLOG_CONFIG_FILE
sed -i -e 's|mongodb_useauth = true|mongodb_useauth = false|' $GRAYLOG_CONFIG_FILE
sed -i -e 's|#elasticsearch_discovery_zen_ping_multicast_enabled = false|elasticsearch_discovery_zen_ping_multicast_enabled = false|' $GRAYLOG_CONFIG_FILE
sed -i -e 's|#elasticsearch_discovery_zen_ping_unicast_hosts = 192.168.1.203:9300|elasticsearch_discovery_zen_ping_unicast_hosts = 127.0.0.1:9300|' $GRAYLOG_CONFIG_FILE

# Setting new retention policy setting or Graylog2 Server will not start
sed -i 's|retention_strategy = delete|retention_strategy = close|' $GRAYLOG_CONFIG_FILE

# This setting is required as of v0.20.2 in $GRAYLOG_CONFIG_FILE
sed -i -e 's|#rest_transport_uri = http://192.168.1.1:12900/|rest_transport_uri = http://127.0.0.1:12900/|' $GRAYLOG_CONFIG_FILE

# change config file path
sed -i -e 's|GRAYLOG_CONF=${GRAYLOG_CONF:=/etc/graylog/server/server.conf}|GRAYLOG_CONF=${GRAYLOG_CONF:='$GRAYLOG_CONFIG_FILE'}|' /opt/graylog2-server/bin/graylogctl
# Create graylog2-server startup script
echo "Creating /etc/init.d/graylog2-server startup script"
(
cat <<'EOF'
#!/bin/bash

### BEGIN INIT INFO
# Provides:          graylog2-server
# Required-Start:    $elasticsearch
# Required-Stop:     $graylog2-web-interface
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start graylog2-server at boot time
# Description:       Starts graylog2-server using start-stop-daemon
### END INIT INFO

CMD=$1

GRAYLOG2_SERVER_CTL=/opt/graylog2-server/bin/graylogctl
GRAYLOG2_CONF=/etc/graylog.conf
GRAYLOG2_PID=/tmp/graylog2.pid
LOG_FILE=/opt/graylog2-server/log/graylog2-server.log

start() {
	${GRAYLOG2_SERVER_CTL} start -f ${GRAYLOG2_CONF}
}

stop() {
    PID=`cat ${GRAYLOG2_PID}`
    echo "Stopping graylog2-server ($PID) ..."
    if kill $PID; then
        rm ${GRAYLOG2_PID}
    fi
}

restart() {
    echo "Restarting graylog2-server ..."
    stop
    start
}

status() {
    pid=$(get_pid)
    if [ ! -z $pid ]; then
        if pid_running $pid; then
            echo "graylog2-server running as pid $pid"
            return 0
        else
            echo "Stale pid file with $pid - removing..."
            rm ${GRAYLOG2_PID}
        fi
    fi

    echo "graylog2-server not running"
}

get_pid() {
    cat ${GRAYLOG2_PID} 2> /dev/null
}

pid_running() {
    kill -0 $1 2> /dev/null
}

case "$CMD" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    status)
        status
        ;;
    *)
        echo "Usage $0 {start|stop|restart|status}"
        RETVAL=1
esac
EOF
) | tee /etc/init.d/graylog2-server

# Make graylog2-server executable
chmod +x /etc/init.d/graylog2-server

# Start graylog2-server on bootup
echo "Making graylog2-server startup on boot"
update-rc.d graylog2-server defaults

echo "Starting graylog2-server"
service graylog2-server start

# Waiting for Graylog2-Server to start accepting requests on tcp/12900
echo "Waiting for Graylog2-Server to start!"
while ! nc -vz localhost 12900; do sleep 1; done

# Install graylog2 web interface
echo "Installing graylog2-web-interface"
ln -s $DOWNLOAD_DIRECTORY/graylog2-web-interface/ graylog2-web-interface

echo "Creating Graylog2-web-interface startup script"
(
cat <<'EOF'
#!/bin/sh

### BEGIN INIT INFO
# Provides:          graylog2-web-interface
# Required-Start:    $graylog2-server
# Required-Stop:     $graylog2-server
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start graylog2-server at boot time
# Description:       Starts graylog2-server using start-stop-daemon
### END INIT INFO

CMD=$1
NOHUP=`which nohup`
JAVA_CMD=/usr/bin/java
GRAYLOG2_WEB_INTERFACE_HOME=/opt/graylog2-web-interface

GRAYLOG2_WEB_INTERFACE_PID=/opt/graylog2-web-interface/RUNNING_PID

start() {
echo "Starting graylog2-web-interface ..."
#sleep 3m
$NOHUP /opt/graylog2-web-interface/bin/graylog-web-interface &
}

stop() {
echo "Stopping graylog2-web-interface ($PID) ..."
PID=`cat ${GRAYLOG2_WEB_INTERFACE_PID}`
if kill $PID; then
        rm ${GRAYLOG2_WEB_INTERFACE_PID}
fi
}

restart() {
echo "Restarting graylog2-web-interface ..."
stop
start
}

status() {
    pid=$(get_pid)
    if [ ! -z $pid ]; then
        if pid_running $pid; then
            echo "graylog2-web-interface running as pid $pid"
            return 0
        else
            echo "Stale pid file with $pid - removing..."
            rm ${GRAYLOG2_WEB_INTERFACE_PID}
        fi
    fi

    echo "graylog2-web-interface not running"
}

get_pid() {
    cat ${GRAYLOG2_WEB_INTERFACE_PID} 2> /dev/null
}

pid_running() {
    kill -0 $1 2> /dev/null
}

case "$CMD" in
        start)
                start
                ;;
        stop)
                stop
                ;;
        restart)
                restart
                ;;
        status)
                status
                ;;
*)
echo "Usage $0 {start|stop|restart|status}"
RETVAL=1
esac
EOF
) | tee /etc/init.d/graylog2-web-interface

# Make graylog2-web-interface executable
chmod +x /etc/init.d/graylog2-web-interface

# Start graylog2-web-interface on bootup
echo "Making graylog2-web-interface startup on boot"
update-rc.d graylog2-web-interface defaults

# Now we need to modify some things to get rsyslog to forward to graylog. this is useful for ESXi syslog format to be correct.
echo "Updating graylog2.conf and rsyslog.conf"
#sed -i -e 's|syslog_listen_port = 514|syslog_listen_port = 10514|' $GRAYLOG_CONFIG_FILE
#sed -i -e 's|#$ModLoad immark|$ModLoad immark|' /etc/rsyslog.conf
sed -i -e 's|#$ModLoad imudp|$ModLoad imudp|' /etc/rsyslog.conf
sed -i -e 's|#$UDPServerRun 514|$UDPServerRun 514|' /etc/rsyslog.conf
sed -i -e 's|#$ModLoad imtcp|$ModLoad imtcp|' /etc/rsyslog.conf
sed -i -e 's|#$InputTCPServerRun 514|$InputTCPServerRun 514|' /etc/rsyslog.conf
sed -i -e 's|*.*;auth,authpriv.none|#*.*;auth,authpriv.none|' /etc/rsyslog.d/50-default.conf
echo '$template GRAYLOG2-1,"<%PRI%>1 %timegenerated:::date-rfc3339% %hostname% %syslogtag% - %APP-NAME%: %msg:::drop-last-lf%\n"' | tee /etc/rsyslog.d/32-graylog2.conf
echo '$template GRAYLOG2-2,"<%pri%>1 %timegenerated:::date-rfc3339% %fromhost% %app-name% %procid% %msg%\n"'  | tee -a /etc/rsyslog.d/32-graylog2.conf
echo '$template GRAYLOGRFC5424,"<%pri%>%protocol-version% %timestamp:::date-rfc3339% %HOSTNAME% %app-name% %procid% %msg%\n"' | tee -a /etc/rsyslog.d/32-graylog2.conf
echo '$PreserveFQDN on' | tee -a  /etc/rsyslog.d/32-graylog2.conf
echo '*.* @localhost:10514;GRAYLOG2-2' | tee -a  /etc/rsyslog.d/32-graylog2.conf
sed -i -e 's|graylog2-server.uris=""|graylog2-server.uris="http://127.0.0.1:12900/"|' $GRAYLOG_WEB_CONFIG_FILE
app_secret=$(pwgen -s 96)
sed -i -e 's|application.secret=""|application.secret="'$app_secret'"|' $GRAYLOG_WEB_CONFIG_FILE

# Fixing /opt/graylog2-web-interface Permissions
echo "Fixing Graylog2 Web Interface Permissions"
chown -R root:root /opt/graylog2*
#chown -R www-data:www-data /opt/graylog2-web-interface*

# Cleaning up /opt
echo "Cleaning up"
rm $DOWNLOAD_DIRECTORY/*tgz -f
rm $DOWNLOAD_DIRECTORY/*deb -f

# Restart All Services
echo "Restarting All Services Required for Graylog2 to work"
service elasticsearch restart
service mongodb restart
service rsyslog restart

echo "Starting graylog2-web-interface"
service graylog2-web-interface start

# All Done
echo "Installation has completed!!"
echo "Browse to IP address of this Graylog2 Server Used for Installation"
echo "IP Address detected from system is $IPADDY"
echo "Browse to http://$IPADDY:9000"
echo "Login with username: admin"
echo "Login with password: $adminpass"
echo "You Entered $SERVERNAME During Install"
echo "Browse to http://$SERVERNAME:9000 If Different"
echo "EveryThingShouldBeVirtual.com"
echo "@mrlesmithjr"
