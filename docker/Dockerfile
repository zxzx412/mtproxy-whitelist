# MTProxy 白名单系统 v4.0 - 修复版
FROM alpine:3.18

# 安装基础依赖
RUN apk update && apk add --no-cache \
    bash \
    curl \
    wget \
    procps \
    bind-tools \
    util-linux \
    coreutils \
    findutils \
    grep \
    sed \
    gawk \
    nginx \
    nginx-mod-stream \
    python3 \
    py3-pip \
    supervisor \
    openssl \
    ca-certificates \
    tar \
    gettext \
    jq \
    && rm -rf /var/cache/apk/*

WORKDIR /app

# 复制项目文件
COPY web/ /usr/share/nginx/html/
COPY api/ /opt/mtproxy-api/
COPY docker/nginx.conf.template /etc/nginx/nginx.conf.template
COPY docker/entrypoint.sh /entrypoint.sh

# 创建目录结构
RUN mkdir -p /data/{nginx,webapp,logs,backup} \
    && mkdir -p /opt/mtproxy \
    && mkdir -p /var/log/{nginx,mtproxy,api} \
    && mkdir -p /etc/nginx/conf.d \
    && mkdir -p /run/nginx

# 安装Python依赖
COPY api/requirements.txt /opt/mtproxy-api/
RUN cd /opt/mtproxy-api && pip3 install --no-cache-dir -r requirements.txt

# 下载MTG程序
RUN cd /opt/mtproxy && \
    ARCH=$(case $(uname -m) in \
        x86_64) echo "amd64" ;; \
        aarch64) echo "arm64" ;; \
        arm*) echo "armv6l" ;; \
        *) echo "amd64" ;; \
    esac) && \
    echo "下载MTG程序 ($ARCH)..." && \
    wget -q https://github.com/9seconds/mtg/releases/download/v1.0.11/mtg-1.0.11-linux-$ARCH.tar.gz -O mtg.tar.gz && \
    tar -xzf mtg.tar.gz mtg-1.0.11-linux-$ARCH/mtg --strip-components 1 && \
    chmod +x mtg && \
    ./mtg --version && \
    rm -f mtg.tar.gz

# 复制重载脚本和统一映射生成脚本
COPY docker/reload-whitelist.sh /usr/local/bin/reload-whitelist.sh
COPY docker/generate-whitelist-map.sh /usr/local/bin/generate-whitelist-map.sh
RUN chmod +x /usr/local/bin/reload-whitelist.sh /usr/local/bin/generate-whitelist-map.sh

# 设置entrypoint权限
RUN chmod +x /entrypoint.sh

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8888/health || exit 1

EXPOSE 443 444 8888

ENTRYPOINT ["/entrypoint.sh"]