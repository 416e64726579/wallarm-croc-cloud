
provider "aws" {
  endpoints {
    ec2 = "https://api.cloud.croc.ru:443"
  }

  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_region_validation      = true
  region                      = var.region
}

resource "aws_instance" "customer_instance" {
  ami                         = var.ami
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  monitoring                  = true
  source_dest_check           = false
  security_groups             = var.security_groups
  associate_public_ip_address = true
  key_name                    = aws_key_pair.wallarm_key_pair.key_name
  user_data                   = <<-EOF
  #cloud-config

  runcmd:
   - apt-get update -y && apt install curl gnupg2 ca-certificates lsb-release
   - echo 'deb http://nginx.org/packages/ubuntu bionic nginx' | tee /etc/apt/sources.list.d/nginx.list
   - curl -fsSL https://nginx.org/keys/nginx_signing.key | apt-key add -
   - apt-get update -y && apt-get install nginx -y
   - apt-key adv --keyserver keys.gnupg.net --recv-keys 72B865FD
   - echo 'deb http://repo.wallarm.com/ubuntu/wallarm-node bionic/2.14/' > /etc/apt/sources.list.d/wallarm.list
   - apt-get update -y && apt-get install -y --no-install-recommends wallarm-node nginx-module-wallarm
   - sed -i 's/SLAB_ALLOC_ARENA=0.2/SLAB_ALLOC_ARENA=${var.tarantool_memory}/g' /etc/default/wallarm-tarantool
   - service wallarm-tarantool restart
   - cp /usr/share/doc/nginx-module-wallarm/examples/*.conf /etc/nginx/conf.d/
   - rm -rf /etc/nginx/conf.d/default.conf
   - /usr/share/wallarm-common/addnode --force -H ${var.wallarm_api_domain} -u ${var.deploy_username} -p ${var.deploy_password} -n ${var.wallarm_hostname}
   - service nginx start

  write_files:
   - path: /etc/nginx/nginx.conf
     owner: root:root
     permissions: '0644'
     content: |
       user nginx;
       worker_processes auto;
       pid /var/run/nginx.pid;
       load_module modules/ngx_http_wallarm_module.so;

       events {
         worker_connections 1024;
         multi_accept on;
         use epoll;
       }

       http {

         ##
         # Basic Settings
         ##

         sendfile on;
         tcp_nopush on;
         tcp_nodelay on;
         keepalive_timeout 30;
         types_hash_max_size 2048;
         server_tokens off;
         send_timeout 5;
         client_max_body_size 0;

         include /etc/nginx/mime.types;
         default_type application/octet-stream;

         ##
         # SSL Settings
         ##

         ssl_protocols TLSv1 TLSv1.1 TLSv1.2; # Dropping SSLv3, ref: POODLE
         ssl_prefer_server_ciphers on;

         ##
         # Logging Settings
         ##
         log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

         access_log /var/log/nginx/access.log main;
         error_log /var/log/nginx/error.log;

         ##
         # Gzip Settings
         ##

         gzip on;

         ##
         # Virtual Host Configs
         ##

         include /etc/nginx/conf.d/*.conf;
         include /etc/nginx/sites-enabled/*;
       }
   - path: /etc/nginx/sites-enabled/default
     owner: root:root
     permissions: '0644'
     content: |
      upstream backend_http {
       server ${var.customer_ip};
       keepalive 10000;
      }

      upstream backend_https {
       server ${var.customer_ip}:443;
       keepalive 10000;
      }

      server {
        listen 80 default_server reuseport;
        server_name ${var.customer_domain};
        wallarm_mode monitoring;

        location / {
          proxy_pass http://backend_http;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

          proxy_http_version 1.1;
          proxy_set_header Connection "";

          set_real_ip_from 172.0.0.0/16;
          real_ip_header X-Forwarded-For;
        }
      }
      server {
        listen 443 ssl default_server reuseport;
        server_name ${var.customer_domain};
        wallarm_mode monitoring;
        ssl_protocols TLSv1.2;
        ssl_ciphers         HIGH:!aNULL:!MD5;
        ssl_certificate /etc/nginx/cert.pem;
        ssl_certificate_key /etc/nginx/key.pem;

        location / {
          proxy_pass https://backend_https;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

          proxy_http_version 1.1;
          proxy_set_header Connection "";

          set_real_ip_from 172.0.0.0/16;
          real_ip_header X-Forwarded-For;
        }
      }
   - path: /etc/nginx/key.pem
     owner: root:root
     permissions: '0600'
     content: "${file("key.pem")}"
   - path: /etc/nginx/cert.pem
     owner: root:root
     permissions: '0644'
     content: "${file("cert.pem")}"
	EOF

  tags = {
    Name        = "Customer WAF"
    Description = "Wallarm Node for the ${var.wallarm_hostname} customer"
  }
}

resource "aws_key_pair" "wallarm_key_pair" {
  key_name   = "tf-wallarm"
  public_key = var.key_pair
}
