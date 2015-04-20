#!/bin/bash
password="password123"

case $1 in
     "ubuntu")
		apt-get update
		apt-get install -y git
        ;;
     "centos")
       	yum -y update
		yum -y install git
        ;;
esac

rm -rf ~/graylog2
git clone https://github.com/mrlesmithjr/graylog2 ~/graylog2

sed -i -e 's|#adminpass=|adminpass='$password'|' ~/graylog2/install_graylog2_90_$1.sh
sed -i -e 's|echo -n "Enter a password to use for the admin account to login to the Graylog2 webUI: "|#echo -n "Enter a password to use for the admin account to login to the Graylog2 webUI: "|' ~/graylog2/install_graylog2_90_$1.sh
sed -i -e 's|read adminpass|#read adminpass|' ~/graylog2/install_graylog2_90_$1.sh
sed -i -e 's|pause 'Press [Enter] key to continue...'|#pause 'Press [Enter] key to continue...'|' ~/graylog2/install_graylog2_90_$1.sh

chmod +x ~/graylog2/install_graylog2_90_$1.sh
sudo bash ~/graylog2/install_graylog2_90_$1.sh

PUBLIC_HOSTNAME="$(curl http://169.254.169.254/latest/meta-data/public-hostname 2>/dev/null)"
echo ""
echo "Public dns for this AWS instance would be http://$PUBLIC_HOSTNAME:9000"
