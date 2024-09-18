#!/bin/bash

read -p "MYSQL Root Password: " -s MYSQL_ROOT_PASSWORD

install_dir="/var/www/html/interview.fireapps.io"
domain="interview.fireapps.io"
sudo mkdir -p $install_dir

if [ -z $MYSQL_ROOT_PASSWORD ]
then
exit 1
fi

sudo apt-get install software-properties-common -y
sudo add-apt-repository ppa:ondrej/php -y
sudo add-apt-repository ppa:certbot/certbot -y
sudo apt update -y 
sudo apt install nginx -y 
sudo systemctl enable --now nginx.service
sudo apt-get install mariadb-server mariadb-client -y 
sudo systemctl enable --now mysql.service
sudo apt-get install python-certbot-nginx -y
sudo apt install php7.2-fpm php7.2-common php7.2-mysql php7.2-gmp php7.2-curl php7.2-intl php7.2-mbstring php7.2-xmlrpc php7.2-gd php7.2-xml php7.2-cli php7.2-zip -y
sudo apt install wget -y
sudo apt install unzip -y
sudo apt install expect -y


mysql -u root <<-EOF
UPDATE mysql.user SET Password=PASSWORD('$MYSQL_ROOT_PASSWORD') WHERE User='root';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN \('localhost', '127.0.0.1', '::1'\);
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.db WHERE Db='test' OR Db='test_%';
FLUSH PRIVILEGES;
EOF


wget https://wordpress.org/latest.zip
unzip latest.zip
sudo cp -a wordpress/* $install_dir
sudo cp $install_dir/wp-config-sample.php $install_dir/wp-config.php
sudo chown -R www-data:www-data $install_dir/
sudo chmod -R 755 $install_dir/

sudo mysql -u root <<-EOF
CREATE DATABASE wordpress;
CREATE USER 'wordpressuser'@'localhost' IDENTIFIED BY 'wordpress';
GRANT ALL ON wordpress.* TO 'wordpressuser'@'localhost' IDENTIFIED BY 'password' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

sudo sed -i "s/database_name_here/wordpress/" $install_dir/wp-config.php
sudo sed -i "s/username_here/wordpressuser/" $install_dir/wp-config.php
sudo sed -i "s/password_here/password/" $install_dir/wp-config.php

sudo mkdir -p /var/lib/letsencrypt/.well-known
sudo chgrp www-data /var/lib/letsencrypt
sudo chmod g+s /var/lib/letsencrypt

cat > /tmp/certbotnginx << EOF
  location ^~ /.well-known/acme-challenge/ {
  allow all;
  root /var/lib/letsencrypt/;
  default_type "text/plain";
  try_files $uri =404;
}
EOF


sudo cp /tmp/certbotnginx /etc/nginx/snippets/well-known

sudo cat > /tmp/$domain << EOF
server {
    listen 80;
    listen [::]:80;

    server_name  $domain;
    root   /var/www/html/$domain;
    index  index.php;
    
    include snippets/well-known;

    access_log /var/log/nginx/$domain.access.log;
    error_log /var/log/nginx/$domain.error.log;

    client_max_body_size 100M;
  
    autoindex off;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ .php$ {
         include snippets/fastcgi-php.conf;
         fastcgi_pass unix:/var/run/php/php7.2-fpm.sock;
         fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
         include fastcgi_params;
    }
}
EOF

sudo ufw allow 'Nginx Full'

sudo cp /tmp/$domain /etc/nginx/sites-available/$domain 
sudo touch /var/log/nginx/$domain.access.log
sudo touch /var/log/nginx/$domain.error.log
sudo chown -R www-data:www-data /var/log/nginx/$domain.*

sudo ln -s /etc/nginx/sites-available/$domain /etc/nginx/sites-enabled/
sudo systemctl restart nginx.service

sudo certbot --nginx -m admin@$domain -d $domain

RUN_certbotE=$(expect -c "

set timeout 10
spawn sudo certbot --nginx -m admin@$domain -d $domain 
expect Y\"(A)gree\/(C)ancel:\"
send \"A\r\"
expect Y\"(Y)es\/(N)o\"
send \"A\r\"
expect Y\"Select the appropriate number \[1-2\] then \[enter\] (press \'c\' to cancel):\"
send \"2\r\"
")
echo "$RUN_certbot"

(crontab -l ; echo "0 1 * * * /usr/bin/certbot renew & > /dev/null") | crontab
