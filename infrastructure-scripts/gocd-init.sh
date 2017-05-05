#!/bin/bash

# WARNING: if you change this file your GOCD server will be
# wiped and recreated from SCRATCH


# some deps
if [[ -z "$(which gcc)" ]];
then
    echo "Updating deps"
    apt-get update
    apt-get install software-properties-common git apt-transport-https dnsutils unzip ca-certificates gnupg2 -y
    apt-get install build-essential curl m4 ruby texinfo libbz2-dev libcurl4-openssl-dev libexpat-dev libncurses-dev zlib1g-dev -y
else
    echo "Not updating deps"
fi


# update DNS
cat > /root/update-dns.sh <<'eofscript'
#!/bin/bash

MY_IP=`curl -s "https://api.ipify.org"`
DNS_NAME=`curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/dns" -H "Metadata-Flavor: Google"`
ZONENAME="project-zone"



dns_start() {
  gcloud dns record-sets transaction start    -z "${ZONENAME}"
}

dns_info() {
  gcloud dns record-sets transaction describe -z "${ZONENAME}"
}

dns_abort() {
  gcloud dns record-sets transaction abort    -z "${ZONENAME}"
}

dns_commit() {
  gcloud dns record-sets transaction execute  -z "${ZONENAME}"
}

dns_add() {
    local -r name=$1
    local -r ttl=$2
    local -r type=$3
    local -r data=$4
    echo "Adding DNS ${name} -> ${data}"
    gcloud dns record-sets transaction add -z "${ZONENAME}" --name "${name}" --ttl "${ttl}" --type "${type}" "${data}"
}

dns_del() {
    local -r name=$1
    local -r ttl=$2
    local -r type=$3
    local -r data=$4
    echo "Removing DNS ${name} -> ${data}"
    gcloud dns record-sets transaction remove -z "${ZONENAME}" --name "${name}" --ttl "${ttl}" --type "${type}" "${data}"
}

lookup_dns_ip() {
  host "$1" | sed -rn 's@^.* has address @@p'
}


OLD_IP=`lookup_dns_ip "$DNS_NAME"`
if [[ $MY_IP != $OLD_IP ]]; then
    echo "About to do DNS update for $DNS_NAME from $OLD_IP -> $MY_IP"
    dns_start
    dns_del "${DNS_NAME}." 300 A "$OLD_IP"
    dns_add "${DNS_NAME}." 300 A "$MY_IP"
    dns_commit
else
    echo "No DNS update needed for $DNS_NAME which already points to our IP: $OLD_IP"
fi

eofscript
chmod +x /root/update-dns.sh
/root/update-dns.sh


# nodeJS
if [[ -z "$(which node)" ]];
then
    echo "Installing Node"
    curl -o- https://deb.nodesource.com/setup_7.x | bash
    apt-get update
    apt-get install nodejs -y
    # some useful things
    npm install -g -y bower grunt gulp
else
    echo "Node already installed"
fi


# terraform
if [[ -z "$(which terraform)" ]];
then
    echo "Installing Terraform"
    wget https://releases.hashicorp.com/terraform/0.9.4/terraform_0.9.4_linux_amd64.zip -O /tmp/terraform.zip
    unzip /tmp/terraform.zip -d /usr/bin
    rm /tmp/terraform.zip
else
    echo "Terraform already installed"
fi


# docker
if [[ -z "$(which docker)" ]];
then
    echo "Installing Docker"
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian jessie stable"
    sudo apt-get update
    sudo apt-get install docker-ce -y
else
    echo "Docker already installed"
fi


# kubectl
if [[ -z "$(which kubectl)" ]];
then
    echo "Installing kubectl"
    curl -L -o /usr/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
    chmod +x /usr/bin/kubectl
else
    echo "kubectl already installed"
fi


# java
if [[ -z "$(which java)" ]];
then
    echo "Installing Java"
    echo "deb http://ppa.launchpad.net/webupd8team/java/ubuntu xenial main" >> /etc/apt/sources.list.d/webupd8team-java.list
    echo "deb-src http://ppa.launchpad.net/webupd8team/java/ubuntu xenial main" >> /etc/apt/sources.list.d/webupd8team-java.list
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys EEA14886
    # accept agreement
    echo debconf shared/accepted-oracle-license-v1-1 select true | debconf-set-selections
    echo debconf shared/accepted-oracle-license-v1-1 seen true | debconf-set-selections
    apt-get update
    apt-get install oracle-java8-installer oracle-java8-set-default -y
    java -version
else
    echo "Java already installed"
fi


# nginx
if [[ ! -f /etc/init.d/nginx ]];
then
    echo "Installing Nginx"
    echo "deb http://nginx.org/packages/debian/ jessie nginx" >> /etc/apt/sources.list.d/nginx.list
    echo "deb-src http://nginx.org/packages/debian/ jessie nginx" >> /etc/apt/sources.list.d/nginx.list
    sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys ABF5BD827BD9BF62
    apt update
    apt install nginx -y
    openssl dhparam 2048 -out /etc/nginx/dhparam.pem
    # temporary config until LE certs are in place
    cat > /etc/nginx/conf.d/default.conf <<EOF
# default server redirects to https except for .well-known
server {
        listen [::]:80;
        listen      80;

        location / {
                return 301 https://\$host\$request_uri;
        }

        location /.well-known {
                root /usr/share/nginx/html;
        }
}
EOF
    /etc/init.d/nginx restart
else
    echo "Nginx already installed"
fi

# gocd
if [[ ! -f /etc/init.d/go-server ]];
then
    echo "Installing Go CD"
    echo "deb https://download.gocd.io /" > /etc/apt/sources.list.d/gocd.list
    curl -s https://download.gocd.io/GOCD-GPG-KEY.asc | apt-key add -
    apt-get update 
    apt-get install go-server go-agent -y
    # start
    /etc/init.d/go-server start
    /etc/init.d/go-agent start

    # some plugins
    PLUGIN_DIR=/var/lib/go-server/plugins/external
    wget https://github.com/tomzo/gocd-yaml-config-plugin/releases/download/0.4.0/yaml-config-plugin-0.4.0.jar -O "$PLUGIN_DIR/yaml-config-plugin-0.4.0.jar"
    wget https://github.com/tomzo/gocd-json-config-plugin/releases/download/0.2.0/json-config-plugin-0.2.jar -O "$PLUGIN_DIR/json-config-plugin-0.2.jar"
    wget https://github.com/gocd-contrib/script-executor-task/releases/download/0.3/script-executor-0.3.0.jar -O "$PLUGIN_DIR/script-executor-0.3.0.jar"
    
    # set admin password
    ADMIN_PASSWORD="cdpasswd"
    echo "admin:$(python -c "import sha;from base64 import b64encode;print b64encode(sha.new('$ADMIN_PASSWORD').digest())")" > /etc/go/passwd
    sed -i -E "s/<server( .*?)\/>/<server \1>\n    <security>\n      <passwordFile path='\/etc\/go\/passwd' \/>\n    <\/security>\n  <\/server>/" /etc/go/cruise-config.xml
    # restart
    /etc/init.d/go-server restart
else
    echo "Go CD already installed"
fi

# cert script
cat > /root/letsencrypt.sh <<'eofscript'
#!/bin/bash

# uncomment for staging
# LE_ENVIRONMENT=--staging

# certbot (letsencrypt certificates)
if [[ ! -f /usr/sbin/certbot-auto ]]; then
    echo "Downloading certbot"
    wget https://dl.eff.org/certbot-auto -O /usr/sbin/certbot-auto
    chmod a+x /usr/sbin/certbot-auto

    # bootstrap certbot-auto
    certbot-auto -q
fi


# some vars
DNS_NAME=`curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/dns" -H "Metadata-Flavor: Google"`
EMAIL=`curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/email" -H "Metadata-Flavor: Google"`
ACCOUNT_DIR=/etc/letsencrypt/accounts/acme-v01.api.letsencrypt.org/directory
CERT_DIR="/etc/letsencrypt/live/$DNS_NAME/"
WEBROOT=/usr/share/nginx/html


# for certbot webroot plugin
if [[ ! -e "$WEBROOT/.well-known" ]]; then
    echo "Creating directory $WEBROOT/.well-known"
    mkdir "$WEBROOT/.well-known"
fi

# register with letsencrypt if needed
if [[ ! -e "$CERT_DIR" ]]; then
    echo "Registering with letsencrypt using email $EMAIL..."
    certbot-auto register --agree-tos -m "$EMAIL" --non-interactive $LE_ENVIRONMENT
fi

# run certbot
if [[ ! -e "$CERT_DIR" ]]; then
    echo "Registering certificate for $DNS_NAME"
    certbot-auto certonly --webroot -w "$WEBROOT" -d "$DNS_NAME" --non-interactive $LE_ENVIRONMENT

# Proper nginx config
if [[ -e "/etc/letsencrypt/live/$DNS_NAME/fullchain.pem" ]]; then

cat > /etc/nginx/conf.d/default.conf <<EOF
# default server redirects to https except for .well-known
server {
        listen [::]:80;
        listen      80;

        location / {
                return 301 https://\$host\$request_uri;
        }

        location /.well-known {
                root /usr/share/nginx/html;
        }
}



# ssl server proxy passes to gocd and has A+ rating on https://www.ssllabs.com/ssltest/
server {
        listen [::]:443 default_server ssl http2;
        listen      443 default_server ssl http2;

        server_name $DNS_NAME;

        ssl_certificate /etc/letsencrypt/live/$DNS_NAME/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$DNS_NAME/privkey.pem;
        ssl_trusted_certificate /etc/letsencrypt/live/$DNS_NAME/chain.pem;
        ssl_dhparam /etc/nginx/dhparam.pem;
        ssl_protocols TLSv1.2 TLSv1.1 TLSv1;
        ssl_prefer_server_ciphers on;
        ssl_ciphers ECDH+AESGCM:ECDH+AES256:ECDH+AES128:DH+3DES:!ADH:!AECDH:!MD5;
        ssl_session_cache shared:SSL:20m;
        ssl_session_timeout 180m;
        ssl_stapling on;
        ssl_stapling_verify on;

        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

        resolver 8.8.8.8 8.8.4.4;

        location / {
            proxy_pass              http://127.0.0.1:8153/;
            proxy_set_header        Host            \$host;
            proxy_set_header        X-Real-IP       \$remote_addr;
            proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header        X-Forwarded-Proto \$scheme;
        }
}

EOF
fi

    /etc/init.d/nginx restart
fi

# and run autorenew always
echo "Attempting cert renew"
certbot-auto renew --quiet --no-self-upgrade --renew-hook "/etc/init.d/nginx restart" $LE_ENVIRONMENT

# add cron job to renew
CRONFILE="/etc/cron.d/certbot"
if [[ ! -f "$CRONFILE" ]]; then
    HOUR1=$((${RANDOM} % 12 + 1))
    HOUR2=$(((${HOUR1} + 11)%24))
    MINUTE=$((${RANDOM} % 60))
    echo "Scheduling cron job for renew to run at $HOUR1:$MINUTE and $HOUR2:$MINUTE"
    echo "$MINUTE $HOUR1,$HOUR2 * * * root /root/letsencrypt.sh" > "$CRONFILE"
fi


# overwrite nginx config


# stuff will reside here:
# Cert: /etc/letsencrypt/live/$DNS_NAME/fullchain.pem
# Chain: /etc/letsencrypt/live/$DNS_NAME/chain.pem
# Key: /etc/letsencrypt/live/$DNS_NAME/privkey.pem


eofscript

# run the script
chmod +x /root/letsencrypt.sh
/root/letsencrypt.sh
