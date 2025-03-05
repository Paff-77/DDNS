#!/bin/bash

# 获取DNS记录ID
get_dns_record_id() {
    local record_type=$1
    curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=${record_type}&name=${CF_SUBDOMAIN}" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" | jq -r '.result[0].id'
}

# 更新DNS记录
update_dns_record() {
    local ip=$1
    local record_type=$2
    local record_id=$(get_dns_record_id "$record_type")
    
    if [ -z "$record_id" ]; then
        echo "无法获取${record_type}记录ID，尝试创建新记录"
        # 创建新记录
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records" \
            -H "Authorization: Bearer ${CF_API_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"${record_type}\",\"name\":\"${CF_SUBDOMAIN}\",\"content\":\"${ip}\",\"ttl\":1,\"proxied\":false}" | jq
    else
        # 更新现有记录
        curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${record_id}" \
            -H "Authorization: Bearer ${CF_API_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"${record_type}\",\"name\":\"${CF_SUBDOMAIN}\",\"content\":\"${ip}\",\"ttl\":1,\"proxied\":false}" | jq
    fi
}

# 检查并安装 jq
if ! command -v jq &> /dev/null; then
    echo "jq 未安装，正在安装..."
    if [ -x "$(command -v yum)" ]; then
        sudo yum install jq -y
    elif [ -x "$(command -v apt-get)" ]; then
        sudo apt-get install jq -y
    else
        echo "无法自动安装 jq，请手动安装。"
        exit 1
    fi
fi

# 安装目录
INSTALL_DIR="/etc/ddns"
SERVICE_NAME="ddns.service"
TIMER_NAME="ddns.timer"
# 创建安装目录
mkdir -p "$INSTALL_DIR"

# 收集用户输入
read -p "请输入你的Cloudflare API令牌: " CF_API_TOKEN
read -p "请输入你的Zone ID: " CF_ZONE_ID
read -p "请输入你要更新的二级域名 (例如：subdomain.yourdomain.com): " CF_SUBDOMAIN
read -p "请输入检测间隔（s）: " UPDATE_TIME

# 询问IP版本选择
echo "请选择DDNS更新模式："
echo "1) 仅IPv4"
echo "2) IPv4和IPv6双栈"
read -p "请输入选项 (1 或 2): " IP_MODE

# 保存配置到.env文件
cat << EOF > "$INSTALL_DIR/ddns.env"
CF_API_TOKEN=$CF_API_TOKEN
CF_ZONE_ID=$CF_ZONE_ID
CF_SUBDOMAIN=$CF_SUBDOMAIN
IP_MODE=$IP_MODE
UPDATE_TIME=$UPDATE_TIME
EOF

# 立即解析当前IP地址并更新DNS记录
if [ "$IP_MODE" = "1" ]; then
    current_ip=$(curl -s -4 https://api.ipify.org || curl -s -4 ip.sb)
    if [ -n "$current_ip" ]; then
        echo "当前IPv4地址: $current_ip"
        update_dns_record "$current_ip" "A"
    else
        echo "无法获取当前IPv4地址"
    fi
elif [ "$IP_MODE" = "2" ]; then
    current_ipv4=$(curl -s -4 https://api.ipify.org || curl -s -4 ip.sb)
    current_ipv6=$(curl -s -6 https://api6.ipify.org || curl -s -6 ip.sb)
    if [ -n "$current_ipv4" ]; then
        echo "当前IPv4地址: $current_ipv4"
        update_dns_record "$current_ipv4" "A"
    else
        echo "无法获取当前IPv4地址"
    fi
    if [ -n "$current_ipv6" ]; then
        echo "当前IPv6地址: $current_ipv6"
        update_dns_record "$current_ipv6" "AAAA"
    else
        echo "无法获取当前IPv6地址"
    fi
fi

# 核心程序脚本
cat << 'EOF' > "$INSTALL_DIR/ddns_updater.sh"
#!/bin/bash

# 加载配置
source /etc/ddns/ddns.env

# 文件路径配置
IPV4_LOG_FILE="/etc/ddns/ipv4.txt"
IPV6_LOG_FILE="/etc/ddns/ipv6.txt"

# 获取DNS记录ID
get_dns_record_id() {
    local record_type=$1
    curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=${record_type}&name=${CF_SUBDOMAIN}" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" | jq -r '.result[0].id'
}

# 更新DNS记录
update_dns_record() {
    local ip=$1
    local record_type=$2
    local record_id=$(get_dns_record_id "$record_type")
    
    if [ -z "$record_id" ]; then
        echo "无法获取${record_type}记录ID，尝试创建新记录"
        # 创建新记录
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records" \
            -H "Authorization: Bearer ${CF_API_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"${record_type}\",\"name\":\"${CF_SUBDOMAIN}\",\"content\":\"${ip}\",\"ttl\":1,\"proxied\":false}" | jq
    else
        # 更新现有记录
        curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${record_id}" \
            -H "Authorization: Bearer ${CF_API_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"${record_type}\",\"name\":\"${CF_SUBDOMAIN}\",\"content\":\"${ip}\",\"ttl\":1,\"proxied\":false}" | jq
    fi
}

# 获取当前IPv4地址
get_current_ipv4() {
    # 尝试使用ipify
    local ip=$(curl -s -4 https://api.ipify.org)
    if [ -z "$ip" ] || [[ ! $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # 如果ipify失败，尝试使用ip.sb
        ip=$(curl -s -4 ip.sb)
    fi
    echo "$ip"
}

# 获取当前IPv6地址
get_current_ipv6() {
    # 尝试使用ipify
    local ip=$(curl -s -6 https://api6.ipify.org)
    if [ -z "$ip" ] || [[ ! $ip =~ ^[0-9a-fA-F:]+$ ]]; then
        # 如果ipify失败，尝试使用ip.sb
        ip=$(curl -s -6 ip.sb)
    fi
    echo "$ip"
}

# 记录当前IP
log_current_ip() {
    local ip=$1
    local log_file=$2
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ${ip}" >> "$log_file"
}

# 检查并更新IPv4
check_and_update_ipv4() {
    current_ip=$(get_current_ipv4)
    if [ -z "$current_ip" ]; then
        echo "无法获取当前IPv4地址"
        return 1
    fi

    if [ ! -f "$IPV4_LOG_FILE" ]; then
        touch "$IPV4_LOG_FILE"
    fi

    last_ip=$(tail -n 1 "$IPV4_LOG_FILE" 2>/dev/null | awk '{print $NF}')
    
    if [ "$current_ip" != "$last_ip" ]; then
        echo "检测到IPv4变化: ${last_ip:-无记录} -> $current_ip"
        log_current_ip "$current_ip" "$IPV4_LOG_FILE"
        update_dns_record "$current_ip" "A"
    else
        echo "IPv4未变化: $current_ip"
    fi
}

# 检查并更新IPv6
check_and_update_ipv6() {
    current_ip=$(get_current_ipv6)
    if [ -z "$current_ip" ]; then
        echo "无法获取当前IPv6地址"
        return 1
    fi

    if [ ! -f "$IPV6_LOG_FILE" ]; then
        touch "$IPV6_LOG_FILE"
    fi

    last_ip=$(tail -n 1 "$IPV6_LOG_FILE" 2>/dev/null | awk '{print $NF}')
    
    if [ "$current_ip" != "$last_ip" ]; then
        echo "检测到IPv6变化: ${last_ip:-无记录} -> $current_ip"
        log_current_ip "$current_ip" "$IPV6_LOG_FILE"
        update_dns_record "$current_ip" "AAAA"
    else
        echo "IPv6未变化: $current_ip"
    fi
}

# 主执行逻辑
if [ "$IP_MODE" = "1" ]; then
    check_and_update_ipv4
elif [ "$IP_MODE" = "2" ]; then
    check_and_update_ipv4
    check_and_update_ipv6
fi
EOF

# 赋予执行权限
chmod +x "$INSTALL_DIR/ddns_updater.sh"

# 创建systemd服务文件
cat << EOF > "/etc/systemd/system/$SERVICE_NAME"
[Unit]
Description=DDNS Updater
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash $INSTALL_DIR/ddns_updater.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

cat << EOF > "/etc/systemd/system/$TIMER_NAME"
[Unit]
Description=DDNS Timer

[Timer]
OnUnitActiveSec=$UPDATE_TIME
OnBootSec=$UPDATE_TIME

[Install]
WantedBy=timers.target
EOF



# 重新加载systemd守护进程
systemctl daemon-reload

# 启用并启动服务
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME
systemctl enable $TIMER_NAME
systemctl start $TIMER_NAME
echo "DDNS服务已安装并启动。"
