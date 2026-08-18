#!/bin/bash
# ============================================================
# 国密 Tengine 部署前体检脚本
# 用法：bash precheck.sh [端口]     （默认端口 443）
# 在目标服务器上执行，全部 PASS 后再启动 Tengine
# ============================================================
PORT="${1:-443}"
FAIL=0

echo "=============================================="
echo " 国密 Tengine 部署前体检（端口 $PORT）"
echo "=============================================="

echo ""
echo "=== 1. 架构检查 ==="
ARCH=$(uname -m)
echo "当前机器架构：$ARCH"
echo "请确认上传的产物包与本架构匹配："
echo "  x86_64  -> tengine-gm-2.4.1-x86_64-centos7-glibc217.tar.gz"
echo "  aarch64 -> tengine-gm-2.4.1-aarch64-kyv10-glibc228.tar.gz"
if [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "aarch64" ]; then
    echo "PASS: 架构受支持"
else
    echo "FAIL: 不支持的架构"
    FAIL=1
fi

echo ""
echo "=== 2. 系统版本与内核 ==="
if [ -f /etc/os-release ]; then
    grep PRETTY_NAME /etc/os-release 2>/dev/null || cat /etc/os-release
elif [ -f /etc/redhat-release ]; then
    cat /etc/redhat-release
fi
uname -r
echo "内核要求：x86_64 产物 >= 2.6.32；aarch64 产物 >= 3.7"

echo ""
echo "=== 3. glibc 版本 ==="
GLIBC_VER=$(ldd --version 2>/dev/null | head -1)
echo "$GLIBC_VER"
echo "要求：x86_64 产物 glibc >= 2.17；aarch64 产物 glibc >= 2.28"

echo ""
echo "=== 4. 动态库依赖检查 ==="
if [ -f /usr/local/tengine/sbin/nginx ]; then
    MISSING=$(ldd /usr/local/tengine/sbin/nginx 2>&1 | grep -i "not found" || true)
    if [ -n "$MISSING" ]; then
        echo "FAIL: 以下动态库缺失："
        echo "$MISSING"
        FAIL=1
    else
        echo "PASS: 全部依赖库在位："
        ldd /usr/local/tengine/sbin/nginx 2>/dev/null | awk '{print $1}' | sort -u | grep -v "^$"
    fi
else
    echo "SKIP: /usr/local/tengine/sbin/nginx 不存在（请先解压产物：tar xzf <包名> -C /usr/local）"
fi

echo ""
echo "=== 5. 端口占用检查 ==="
if netstat -tlnp 2>/dev/null | grep -q ":${PORT} " || ss -tlnp 2>/dev/null | grep -q ":${PORT} "; then
    echo "WARN: 端口 ${PORT} 已被占用："
    netstat -tlnp 2>/dev/null | grep ":${PORT} " || ss -tlnp 2>/dev/null | grep ":${PORT} "
else
    echo "PASS: 端口 ${PORT} 空闲"
fi

echo ""
echo "=== 6. SELinux 状态（CentOS 系）==="
if command -v getenforce >/dev/null 2>&1; then
    MODE=$(getenforce 2>/dev/null)
    echo "SELinux 状态：$MODE"
    if [ "$MODE" = "Enforcing" ]; then
        echo "WARN: SELinux 为 Enforcing。若启动后出现访问 403/超时，先 setenforce 0 验证；"
        echo "      生产环境请配置策略或保持关闭。"
    fi
else
    echo "本系统无 SELinux"
fi

echo ""
echo "=== 7. 防火墙状态 ==="
if systemctl is-active firewalld >/dev/null 2>&1; then
    echo "WARN: firewalld 运行中，请放行 ${PORT} 端口："
    echo "  firewall-cmd --add-port=${PORT}/tcp --permanent && firewall-cmd --reload"
elif command -v iptables >/dev/null 2>&1; then
    echo "提示：未检测到 firewalld，请人工确认 iptables 规则放行 ${PORT}"
else
    echo "PASS: 未检测到活动防火墙服务"
fi

echo ""
echo "=== 8. 磁盘空间 ==="
df -h /usr/local 2>/dev/null | tail -1
echo "要求可用空间 >= 100M"

echo ""
echo "=== 9. 运行用户检查（systemd 方式需确认）==="
id nginx >/dev/null 2>&1 && echo "PASS: nginx 用户已存在" || echo "提示：nginx 用户不存在。直接以 root 启动无需此用户；若配置降权运行，请先 useradd -r nginx"

echo ""
echo "=============================================="
if [ "$FAIL" = "1" ]; then
    echo " 体检结论：存在阻塞项（FAIL），处理后重新执行"
    exit 1
else
    echo " 体检结论：通过（WARN 项不影响启动，建议处理）"
    echo " 下一步：放置证书 -> 配置 nginx.conf -> nginx -t -> 启动"
    exit 0
fi
