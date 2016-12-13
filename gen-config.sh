#!/usr/bin/env bash

set -u
set -e
: ${DOMAIN:=docker.many-it.com} #域名，如果通过IP访问，那么就配置IP
: ${SSLCERT:=domain.cer}		#域名的 SSL 证书
: ${SSLKEY:=domain.key}			#域名的 SSL 证书的私钥
: ${HTTP_PORT:=80}				#端口
: ${HTTPS_PORT:=443}			#HTTPS 端口
: ${STATUS:=health_status}		#健康状态的Url
: ${CHECK_URL:=/plb/ver.txt} 	#通过获取CHECK_URL判断服务器是否活的状态


cat <<- EOF > file
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;

events {
    worker_connections 1024;
}

http {
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 2048;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

	upstream cluster-tomcat{
		fair;
		
		server 192.188.188.12:8088;
		server 192.188.188.18:80;
		
		sticky name=srv_id;
		check interval=5000 rise=2 fall=5 timeout=1000 type=http; 
		check_http_send "GET ${CHECK_URL} HTTP/1.0\r\n\r\n"; 
	}

	# HTTP 重定向到 HTTPS，此处 HTTP 是 8088 端口
	server {
		listen ${HTTP_PORT};
		server_name ${DOMAIN};
		rewrite ^(.*) https://\$server_name\$1 permanent;
	}

	# HTTPS server
	server {
		listen       ${HTTPS_PORT} ssl http2;
		server_name  ${DOMAIN};

		ssl_certificate      ${SSLCERT};
		ssl_certificate_key  ${SSLKEY};

		ssl_dhparam /root/dhparams/dhparam.pem;
		ssl_ciphers 'ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-DSS-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA256:DHE-RSA-AES256-SHA:DHE-DSS-AES256-SHA:DHE-RSA-CAMELLIA256-SHA:DHE-DSS-CAMELLIA256-SHA:ECDH-RSA-AES256-GCM-SHA384:ECDH-ECDSA-AES256-GCM-SHA384:ECDH-RSA-AES256-SHA384:ECDH-ECDSA-AES256-SHA384:ECDH-RSA-AES256-SHA:ECDH-ECDSA-AES256-SHA:AES256-GCM-SHA384:AES256-SHA256:AES256-SHA:CAMELLIA256-SHA:PSK-AES256-CBC-SHA:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:DHE-DSS-AES128-GCM-SHA256:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES128-SHA256:DHE-DSS-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA:DHE-RSA-SEED-SHA:DHE-DSS-SEED-SHA:DHE-RSA-CAMELLIA128-SHA:DHE-DSS-CAMELLIA128-SHA:ECDH-RSA-AES128-GCM-SHA256:ECDH-ECDSA-AES128-GCM-SHA256:ECDH-RSA-AES128-SHA256:ECDH-ECDSA-AES128-SHA256:ECDH-RSA-AES128-SHA:ECDH-ECDSA-AES128-SHA:AES128-GCM-SHA256:AES128-SHA256:AES128-SHA:SEED-SHA:CAMELLIA128-SHA:PSK-AES128-CBC-SHA:ECDHE-RSA-DES-CBC3-SHA:ECDHE-ECDSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:EDH-DSS-DES-CBC3-SHA:ECDH-RSA-DES-CBC3-SHA:ECDH-ECDSA-DES-CBC3-SHA:DES-CBC3-SHA:IDEA-CBC-SHA:PSK-3DES-EDE-CBC-SHA:KRB5-IDEA-CBC-SHA:KRB5-DES-CBC3-SHA:KRB5-IDEA-CBC-MD5:KRB5-DES-CBC3-MD5:ECDHE-RSA-RC4-SHA:ECDHE-ECDSA-RC4-SHA:ECDH-RSA-RC4-SHA:ECDH-ECDSA-RC4-SHA:RC4-SHA:RC4-MD5:PSK-RC4-SHA:KRB5-RC4-SHA:KRB5-RC4-MD5';
		ssl_prefer_server_ciphers  on;
		ssl_session_timeout 1d;
		ssl_session_cache shared:SSL:10m;
		add_header Strict-Transport-Security max-age=15768000;
		add_header X-Frame-Options DENY;
		add_header X-Content-Type-Options nosniff;
		ssl_stapling on;
		ssl_stapling_verify on;

		location / {  
			proxy_pass http://cluster-tomcat;

			proxy_set_header  X-Real-IP  \$remote_addr;
			proxy_set_header  X-Forwarded-For \$proxy_add_x_forwarded_for;
			proxy_set_header  Host \$host;
			proxy_set_header  X-Forwarded-Protocol \$scheme;
			proxy_set_header  X-Forwarded-Proto \$scheme;
			
			proxy_redirect off;
		}
		
		location /${STATUS} {
			check_status;
		}
	}
}
EOF

