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

read -s -p "Enter PostgreSQL password for user $USERNAME: " PGPASSWORD
echo

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no root@"$BEST_SERVER" << EOF
#!/bin/bash
set -e

echo "Installation on $BEST_SERVER"

if which apt; then
  echo "Debian-based system"
  apt update && apt install -y postgresql-15
  APT_STATUS=\$?
  if [ "\$APT_STATUS" -ne "0" ]; then
    echo "Error: install failed with status \$APT_STATUS"
    exit 1
  fi
  PG_HBA_CONF="/etc/postgresql/15/main/pg_hba.conf"
  PG_CONF="/etc/postgresql/15/main/postgresql.conf"

elif which yum; then
  echo "CentOS-based system"
  yum install -y postgresql15-server postgresql15
   YUM_STATUS=\$?
  if [ "\$YUM_STATUS" -ne "0" ]; then
    echo "Error: install failed with status \$YUM_STATUS"
    exit 1
  fi
  postgresql-setup --version 15 initdb
  systemctl enable postgresql-15
  systemctl start postgresql-15
  PG_HBA_CONF="/var/lib/pgsql/15/data/pg_hba.conf"
  PG_CONF="/var/lib/pgsql/15/data/postgresql.conf"

echo "host all all 0.0.0.0/0 md5" >> "\$PG_HBA_CONF"
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" "\$PG_CONF"
systemctl restart postgresql@15-main.service

second_server_ip=\$(echo "$SERVER_IPS" | awk '{print \$2}')

sudo -u postgres -H psql -U postgres -c "CREATE USER $USERNAME WITH PASSWORD '$PGPASSWORD';"
CREATE_USER_STATUS=\$?
if [ "\$CREATE_USER_STATUS" -ne "0" ]; then
  echo "Error: CREATE USER failed with status \$CREATE_USER_STATUS"
  exit 1
fi

sudo -u postgres -H psql -U postgres -c "CREATE DATABASE $USERNAME OWNER $USERNAME;"
CREATE_DB_STATUS=\$?
if [ "\$CREATE_DB_STATUS" -ne "0" ]; then
  echo "Error: CREATE DATABASE failed with status \$CREATE_DB_STATUS)"
  exit 1
fi

if [ -n "$second_server_ip" ]; then
  echo "host $USERNAME $USERNAME $second_server_ip/32 md5" >> "\$PG_HBA_CONF"
fi
systemctl restart postgresql@15-main.service

echo "Installation complete"
exit
EOF

echo "The script has been executed"