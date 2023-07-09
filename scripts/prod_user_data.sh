#!/bin/bash
sudo apt-get update

sudo bash -c 'cat <<'EOF' >/home/ubuntu/docker-compose.yml
frontend:
    image: frontend-prod
    container_name: frontend
    ports:
        - "8080:80"
    restart: always
admin:
    image: admin-prod
    container_name: admin
    ports:
        - "90:80"
    restart: always
api:
    image: api-prod
    container_name: api
    ports:
        - "8090:5000"
    restart: always
netdata:
    image: docker.io/netdata/netdata
    container_name: netdata
    hostname: "${hostname}"
    ports:
    - 19999:19999
    restart: unless-stopped
    cap_add:
    - SYS_PTRACE
    security_opt:
    - apparmor:unconfined
    environment:
    - PGID=${pgid}
    - PUID=0
    volumes:
    - ${home}/data/netdata_lib:/var/lib/netdata
    - ${home}/data/netdata_cache:/var/cache/netdata
    - /etc/passwd:/host/etc/passwd:ro
    - /etc/group:/host/etc/group:ro
    - /proc:/host/proc:ro
    - /sys:/host/sys:ro
    - /etc/os-release:/host/etc/os-release:ro
    - /var/run/docker.sock:/var/run/docker.sock
EOF'

sudo bash -c 'cat <<'EOF' >/home/ubuntu/pocketpropertiesapp
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name pocketpropertiesapp.com www.pocketpropertiesapp.com _;

    location / {
        proxy_pass http://localhost:8080;
        include proxy_params;
    }
}

server {
    listen 80;
    listen [::]:80;

    server_name admin.pocketpropertiesapp.com;

    location / {
        proxy_pass http://localhost:90;
        include proxy_params;
    }
}

server {
    listen 80;
    listen [::]:80;

    server_name api.pocketpropertiesapp.com;

    location /api {
        proxy_pass http://localhost:8090;
        include proxy_params;
    }
}
EOF'


cd $HOME
sudo apt-get install nginx -y

sudo systemctl start nginx
sudo systemctl enable nginx
sudo cp /home/ubuntu/pocketpropertiesapp /etc/nginx/sites-available/
sudo ln -s /etc/nginx/sites-available/pocketpropertiesapp /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx


sudo apt-get install -y docker.io
curl -L "https://github.com/docker/compose/releases/download/1.29.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

sudo groupadd docker
sudo usermod -aG docker ${USER}

sudo apt-get install -y awscli


sudo aws ecr --region "us-east-1" get-login-password |   sudo docker login --username AWS --password-stdin  "829465433345.dkr.ecr.us-east-1.amazonaws.com/equity-prod"

cd /home/ubuntu

sudo docker-compose down
sudo docker rm $(sudo docker ps -q) -f
sudo docker rmi $(sudo docker images -q) -f

sudo docker pull 829465433345.dkr.ecr.us-east-1.amazonaws.com/equity-prod:frontend-prod
sudo docker tag  829465433345.dkr.ecr.us-east-1.amazonaws.com/equity-prod:frontend-prod frontend-prod

sudo docker pull 829465433345.dkr.ecr.us-east-1.amazonaws.com/equity-prod:api-prod
sudo docker tag  829465433345.dkr.ecr.us-east-1.amazonaws.com/equity-prod:api-prod api-prod

sudo docker pull 829465433345.dkr.ecr.us-east-1.amazonaws.com/equity-prod:admin-prod
sudo docker tag  829465433345.dkr.ecr.us-east-1.amazonaws.com/equity-prod:admin-prod admin-prod
sudo docker-compose up -d
