#!/bin/bash
dnf install -y httpd mariadb105
systemctl enable --now httpd
echo "<h1>Hello from lab-web</h1>" > /var/www/html/index.html
