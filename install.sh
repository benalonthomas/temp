set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "no root"
  exit 1
fi

apt update
apt install -y vim curl wget python3-venv

readonly GADS_URL="https://github.com/benalonthomas/temp/releases/latest/download/gads.tar.gz"
readonly GADS_ARCHIVE="/www/gads.tar.gz"
readonly GADS_ROOT="/www/gads"

readonly GADS_WEB_URL="https://github.com/benalonthomas/temp/releases/latest/download/gads-web.tar.gz"
readonly GADS_WEB_ARCHIVE="/www/gads-web.tar.gz"
readonly GADS_WEB_ROOT="/www/gads-web"

get_public_ip(){
    wget -qO- --timeout=15 --inet4-only https://api.ipify.org
}

install_nginx() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    if ! dpkg -s nginx >/dev/null 2>&1; then
        apt-get install -y nginx ca-certificates
    fi
    if [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1; then
        systemctl enable --now nginx
    fi
}

create_www_layout(){
    mkdir -p /www \
             /www/wwwroot \
             /www/ssh \
             /www/logs
}

download_file(){
    local url="$1"
    local path="$2"
    wget -q --show-progress -O "$path" "$url"
}

install_gads(){
    download_file "$GADS_URL" "$GADS_ARCHIVE"
    mkdir -p "$GADS_ROOT"
    tar --warning=no-unknown-keyword -zxf "$GADS_ARCHIVE" -C "$GADS_ROOT"
    rm "$GADS_ARCHIVE"

    cd "$GADS_ROOT"
    if [[ ! -d "venv" ]]; then
        python3 -m venv venv
    fi
    source "venv/bin/activate"
    pip install -r "requirements/ubuntu.txt"
    pip install geoip2
    flask dbm init
    flask dbm systemd
}

install_gads_web(){
    download_file "$GADS_WEB_URL" "$GADS_WEB_ARCHIVE"
    if [[ -d "$GADS_WEB_ROOT" ]]; then
        rm -rf "$GADS_WEB_ROOT"
    fi
    mkdir -p "$GADS_WEB_ROOT"
    tar --warning=no-unknown-keyword -zxf "$GADS_WEB_ARCHIVE" -C "$GADS_WEB_ROOT"
    rm "$GADS_WEB_ARCHIVE"

    local public_ip="$(get_public_ip)"
    echo "$public_ip"

    local conf_path="/etc/nginx/conf.d/${public_ip}.conf"
    echo "$conf_path"

    cat >"$conf_path" <<EOF
server {
    listen 80;
    server_name ${public_ip};

    root ${GADS_WEB_ROOT};
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF

    nginx -t
    nginx -s reload
}

install_nginx
create_www_layout
install_gads
install_gads_web
