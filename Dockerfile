FROM centos:centos7
MAINTAINER Gu Yanfeng <gyf@many-it.com>

#RUN yum clean all && yum update -y && yum clean all && rpm --rebuilddb
#ONBUILD RUN yum clean all && yum update -y && yum clean all && rpm --rebuilddb

# Install required packages for building nginx
RUN rpm --rebuilddb && \
    yum install -y yum-utils epel-release && \
    yum-config-manager --enable cr && \
    yum install -y bind-utils gc gcc gcc-c++ pcre-devel zlib-devel make patch wget openssl openssl-devel libxml2-devel libxslt-devel gd-devel perl-ExtUtils-Embed GeoIP-devel gperftools gperftools-devel libatomic_ops-devel perl-ExtUtils-Embed git

# Create dhparams
WORKDIR /root
RUN mkdir /root/dhparams
RUN openssl dhparam -out /root/dhparams/dhparam.pem 2048

ENV NGINX_VERSION 1.11.6
# Get all necessary resources
WORKDIR /
RUN curl -o nginx.tar.gz http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz && \
    useradd nginx && \
    usermod -s /sbin/nologin nginx && \
    tar -xvzf nginx.tar.gz && \
    mv nginx-${NGINX_VERSION} nginx
RUN git clone https://bitbucket.org/nginx-goodies/nginx-sticky-module-ng.git
RUN git clone https://github.com/yaoweibin/nginx_upstream_check_module.git
RUN git clone https://github.com/paranoiagu/nginx-upstream-fair.git

# Build nginx
WORKDIR /nginx-upstream-fair
RUN patch -p1 < /nginx_upstream_check_module/upstream_fair.patch

WORKDIR /nginx-sticky-module-ng
RUN patch -p0 < /nginx_upstream_check_module/nginx-sticky-module.patch 

WORKDIR /nginx
RUN patch -p0 < /nginx_upstream_check_module/check_1.11.5+.patch 
RUN ./configure --user=nginx --group=nginx --sbin-path=/usr/sbin/nginx \
				--conf-path=/etc/nginx/nginx.conf \
				--error-log-path=/var/log/nginx/error.log \
				--http-log-path=/var/log/nginx/access.log  \
				--pid-path=/var/run/nginx.pid \
				--with-select_module \
				--with-poll_module \
				--with-file-aio \
				--with-http_ssl_module \
				--with-http_realip_module \
				--with-http_addition_module \
				--with-http_xslt_module \
				--with-http_image_filter_module \
				--with-http_geoip_module \
				--with-http_sub_module \
				--with-http_dav_module \
				--with-http_flv_module \
				--with-http_mp4_module \
				--with-http_gunzip_module \
				--with-http_gzip_static_module \
				--with-http_auth_request_module \
				--with-http_random_index_module \
				--with-http_secure_link_module \
				--with-http_degradation_module \
				--with-http_stub_status_module \
				--with-http_perl_module \
				--with-mail \
				--with-mail_ssl_module \
				--with-cpp_test_module \
				--with-cpu-opt=CPU \
				--with-pcre \
				--with-pcre-jit \
				--with-zlib-asm=CPU \
				--with-libatomic \
				--with-debug \
				--with-ld-opt="-Wl,-E" \
				--with-http_v2_module \
				--add-module=/nginx-sticky-module-ng \
				--add-module=/nginx_upstream_check_module \
				--add-module=/nginx-upstream-fair

RUN make
RUN make install

# Clear
RUN rm -rf /nginx && \
	rm -rf /nginx-sticky-module-ng && \
	rm -rf /nginx.tar.gz && \
	rm -rf /nginx_upstream_check_module && \
	rm -rf /nginx-upstream-fair

RUN ln -s /dev/stderr /var/log/nginx/error.log && \
    ln -s /dev/stdout /var/log/nginx/access.log && \
    mkdir -p /usr/share/nginx/html

COPY domain.key /etc/nginx/domain.key
COPY domain.cer /etc/nginx/domain.cer

COPY entry-point.sh /entry-point.sh
COPY gen-config.sh /gen-config.sh
COPY loop.sh /loop.sh

ENTRYPOINT ["/entry-point.sh"]
CMD ["/loop.sh"]
