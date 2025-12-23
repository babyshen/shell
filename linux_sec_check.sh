#!/bin/bash

# Linux安全排查脚本
# 适配RedHat系列Linux (Rocky Linux, CentOS, RHEL等)
# 作者: babyshen
# 版本: 1.0

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 输出函数
print_header() {
	echo -e "${BLUE}========================================${NC}"
	echo -e "${BLUE}$1${NC}"
	echo -e "${BLUE}========================================${NC}"
}

print_section() {
	echo -e "${GREEN}===== $1 =====${NC}"
}

print_warning() {
	echo -e "${YELLOW}[警告] $1${NC}"
}

print_error() {
	echo -e "${RED}[错误] $1${NC}"
}

# 检查是否为root用户
check_root() {
	if [[ $EUID -ne 0 ]]; then
		print_warning "建议使用root权限运行此脚本以获取完整信息"
	fi
}

# 获取系统基本信息
get_system_info() {
	print_section "系统基本信息"

	echo "主机名: $(hostname)"
	echo "操作系统: $(cat /etc/redhat-release 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
	echo "内核版本: $(uname -r)"
	echo "系统架构: $(uname -m)"
	echo "系统时间: $(date '+%Y-%m-%d %H:%M:%S %Z')"
	echo "运行时间: $(uptime -p 2>/dev/null || uptime)"
	echo "当前用户: $(whoami)"
	echo "用户数: $(who | wc -l)"
	echo ""
}

# 获取CPU和内存占用高的进程
get_high_resource_processes() {
	print_section "CPU和内存占用高的进程"

	echo "=== CPU占用前10的进程 ==="
	ps aux --sort=-%cpu | head -11 | awk 'NR==1{print $0} NR>1{printf "%-8s %-6s %-6s %-6s %-10s %-6s %-6s %s\n", $1,$2,$3,$4,$5,$6,$7,$11}'

	echo ""
	echo "=== 内存占用前10的进程 ==="
	ps aux --sort=-%mem | head -11 | awk 'NR==1{print $0} NR>1{printf "%-8s %-6s %-6s %-6s %-10s %-6s %-6s %s\n", $1,$2,$3,$4,$5,$6,$7,$11}'

	echo ""
	echo "=== 系统负载情况 ==="
	uptime
	echo ""
}

# 获取网络连接信息
get_network_info() {
	print_section "网络连接信息"

	echo "=== 活跃的网络连接 ==="
	netstat -tuln 2>/dev/null | grep LISTEN || ss -tuln | grep LISTEN

	echo ""
	echo "=== TCP连接统计 ==="
	netstat -an 2>/dev/null | grep -c tcp || ss -an | grep tcp | wc -l

	echo ""
	echo "=== UDP连接统计 ==="
	netstat -an 2>/dev/null | grep -c udp || ss -an | grep udp | wc -l

	echo ""
	echo "=== 网络接口信息 ==="
	ip addr show 2>/dev/null || ifconfig

	echo ""
	echo "=== 路由表 ==="
	ip route 2>/dev/null || route -n

	echo ""
}

# 获取端口监听情况
get_listening_ports() {
	print_section "端口监听情况"

	echo "=== 监听的TCP端口 ==="
	netstat -tlnp 2>/dev/null | grep LISTEN || ss -tlnp | grep LISTEN

	echo ""
	echo "=== 监听的UDP端口 ==="
	netstat -ulnp 2>/dev/null || ss -ulnp

	echo ""
	echo "=== 高风险端口检查 ==="
	local high_risk_ports=(21 22 23 25 53 80 110 143 443 993 995 1433 3306 3389 5432 6379)
	for port in "${high_risk_ports[@]}"; do
		if netstat -tln 2>/dev/null | grep ":$port " >/dev/null || ss -tln | grep ":$port " >/dev/null; then
			print_warning "端口 $port 正在监听"
		fi
	done
	echo ""
}

# 获取SSH登录情况
get_ssh_info() {
	print_section "SSH登录情况"

	echo "=== 当前SSH登录用户 ==="
	who

	echo ""
	echo "=== SSH登录历史 (最近20条) ==="
	if [ -f /var/log/secure ]; then
		grep "Accepted password\|Accepted publickey" /var/log/secure | tail -20
	elif [ -f /var/log/auth.log ]; then
		grep "Accepted password\|Accepted publickey" /var/log/auth.log | tail -20
	fi

	echo ""
	echo "=== SSH失败登录记录 (最近10条) ==="
	if [ -f /var/log/secure ]; then
		grep "Failed password" /var/log/secure | tail -10
	elif [ -f /var/log/auth.log ]; then
		grep "Failed password" /var/log/auth.log | tail -10
	fi

	echo ""
	echo "=== SSH配置检查 ==="
	if [ -f /etc/ssh/sshd_config ]; then
		echo "Root登录设置: $(grep "^PermitRootLogin" /etc/ssh/sshd_config || echo "未设置，使用默认值")"
		echo "密码认证: $(grep "^PasswordAuthentication" /etc/ssh/sshd_config || echo "未设置，使用默认值")"
		echo "空密码: $(grep "^PermitEmptyPasswords" /etc/ssh/sshd_config || echo "未设置，使用默认值")"
	fi
	echo ""
}

# 获取定时任务
get_cron_info() {
	print_section "定时任务"

	echo "=== 系统定时任务 ==="
	cat /etc/crontab 2>/dev/null || echo "无系统定时任务"

	echo ""
	echo "=== 用户定时任务 ==="
	for user in $(ls /var/spool/cron/ 2>/dev/null); do
		echo "--- 用户 $user 的定时任务 ---"
		cat /var/spool/cron/$user 2>/dev/null || echo "无定时任务"
	done

	echo ""
	echo "=== 系统定时任务目录 ==="
	echo "/etc/cron.hourly/ 内容:"
	ls -la /etc/cron.hourly/ 2>/dev/null || echo "目录不存在"

	echo ""
	echo "/etc/cron.daily/ 内容:"
	ls -la /etc/cron.daily/ 2>/dev/null || echo "目录不存在"

	echo ""
	echo "/etc/cron.weekly/ 内容:"
	ls -la /etc/cron.weekly/ 2>/dev/null || echo "目录不存在"

	echo ""
	echo "/etc/cron.monthly/ 内容:"
	ls -la /etc/cron.monthly/ 2>/dev/null || echo "目录不存在"

	echo ""
}

# 获取systemd服务信息
get_systemd_services() {
	print_section "Systemd服务状态"

	echo "=== 启用的服务 ==="
	systemctl list-unit-files --type=service --state=enabled --no-pager 2>/dev/null || service --status-all 2>/dev/null

	echo ""
	echo "=== 失败的服务 ==="
	systemctl --failed --no-pager 2>/dev/null || echo "无法获取失败服务信息"

	echo ""
	echo "=== 重要服务状态 ==="
	local important_services=("sshd" "firewalld" "iptables" "network" "systemd-resolved" "httpd" "nginx" "mysqld" "postgresql")
	for service in "${important_services[@]}"; do
		if systemctl list-unit-files | grep -q "^$service.service"; then
			status=$(systemctl is-active $service 2>/dev/null)
			enabled=$(systemctl is-enabled $service 2>/dev/null)
			echo "$service.service: $status (启用状态: $enabled)"
		fi
	done

	echo ""
}

# 获取安全相关检查
get_security_info() {
	print_section "安全相关检查"

	echo "=== 防火墙状态 ==="
	if command -v firewall-cmd >/dev/null 2>&1; then
		firewall-cmd --state 2>/dev/null && echo "firewalld 运行中" || echo "firewalld 未运行"
		firewall-cmd --list-all 2>/dev/null || echo "无法获取防火墙规则"
	elif command -v iptables >/dev/null 2>&1; then
		echo "iptables规则:"
		iptables -L -n 2>/dev/null || echo "无法获取iptables规则"
	else
		echo "未检测到防火墙"
	fi

	echo ""
	echo "=== SELinux状态 ==="
	if command -v getenforce >/dev/null 2>&1; then
		getenforce
	else
		echo "SELinux未安装或不可用"
	fi

	echo ""
	echo "=== 用户账户信息 ==="
	echo "系统用户列表:"
	cat /etc/passwd | cut -d: -f1,3,7 | grep -E "^[^:]+:[0-9]{1,3}:" | sort

	echo ""
	echo "具有sudo权限的用户:"
	if [ -f /etc/sudoers ]; then
		grep -E "^[^#].*ALL=\(ALL\)" /etc/sudoers /etc/sudoers.d/* 2>/dev/null | cut -d: -f1
	fi

	echo ""
	echo "=== 最近登录的用户 ==="
	lastlog | grep -v "**Never" | head -10

	echo ""
	echo "=== 密码策略 ==="
	if [ -f /etc/login.defs ]; then
		echo "密码最大天数: $(grep "^PASS_MAX_DAYS" /etc/login.defs | awk '{print $2}')"
		echo "密码最小天数: $(grep "^PASS_MIN_DAYS" /etc/login.defs | awk '{print $2}')"
		echo "密码最小长度: $(grep "^PASS_MIN_LEN" /etc/login.defs | awk '{print $2}')"
	fi

	echo ""
	echo "=== 磁盘使用情况 ==="
	df -h

	echo ""
	echo "=== 查找SUID文件 ==="
	find / -type f -perm -4000 -ls 2>/dev/null | head -20

	echo ""
}

# 获取进程和服务信息
get_process_info() {
	print_section "进程和服务信息"

	echo "=== 总进程数 ==="
	ps aux | wc -l

	echo ""
	echo "=== 运行中的关键服务 ==="
	ps aux | grep -E "(sshd|httpd|nginx|mysql|postgres|cron)" | grep -v grep

	echo ""
	echo "=== 僵尸进程 ==="
	ps aux | awk '$8 ~ /^Z/ {print $0}' || echo "无僵尸进程"

	echo ""
}

# 主函数
main() {
	print_header "Linux系统安全排查报告"
	echo "报告生成时间: $(date)"
	echo "检查主机: $(hostname)"
	echo ""

	check_root
	get_system_info
	get_high_resource_processes
	get_network_info
	get_listening_ports
	get_ssh_info
	get_cron_info
	get_systemd_services
	get_security_info
	get_process_info

	print_header "安全排查完成"
	echo "请检查上述输出中的警告信息和异常情况"
}

# 执行主函数
main "$@"
