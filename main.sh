#!/bin/bash

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <server_ips> <ssh_key>"
  exit 1
fi

SERVER_IPS=$(echo "$1" | tr ',' ' ')
SSH_KEY="$2"
USERNAME="student"

BEST_SERVER=""
BEST_LOAD=9999

for ip in $SERVER_IPS; do
  load=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no root@"$ip" "uptime | awk '{print \$(NF-2)}' | tr -d ,")

  if [ -n "$load" ]; then
    if [ $(echo "$load < $BEST_LOAD" | bc) -eq 1 ]; then
      BEST_LOAD="$load"
      BEST_SERVER="$ip"
    fi
  else
    echo "Warning: Could not get load from $ip"
  fi
done

if [ -z "$BEST_SERVER" ]; then
  echo "Error: Could not determine best server."
  exit 1
fi

echo "Server $BEST_SERVER selected"

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no root@"$BEST_SERVER" << EOF
#!/bin/bash
set -e

echo "Installation on $BEST_SERVER"

if which apt; then
  echo "Debian-based system"
  apt update && apt install -y postgresql
else
  echo "CentOS-based system"
  yum install -y postgresql-server postgresql
  postgresql-setup initdb
  systemctl enable postgresql
  systemctl start postgresql
fi

echo "host all all 0.0.0.0/0 md5" >> /var/lib/pgsql/data/pg_hba.conf
echo "host all all 0.0.0.0/0 md5" >> /etc/postgresql/15/main/pg_hba.conf
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /var/lib/pgsql/data/postgresql.conf /etc/postgresql/15/main/postgresql.conf
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /etc/postgresql/15/main/postgresql.conf
systemctl restart postgresql

second_server_ip=\$(echo "$SERVER_IPS" | awk '{print \$2}')
sudo -u postgres psql -c "CREATE USER $USERNAME WITH PASSWORD 'qwerty';"
sudo -u postgres psql -c "CREATE DATABASE $USERNAME OWNER $USERNAME;"
echo "host $USERNAME $USERNAME $second_server_ip/32 md5" >> /var/lib/pgsql/data/pg_hba.conf
echo "host $USERNAME $USERNAME $second_server_ip/32 md5" >> /etc/postgresql/15/main/pg_hba.conf
systemctl restart postgresql

echo "Installation complete"
exit
EOF

echo "The script has been executed"