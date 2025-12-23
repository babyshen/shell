#!/usr/bin/env bash

# A script to configure bonded network interfaces using NetworkManager
# Author:

set -euo pipefail

RED=$(tput setaf 1 2>/dev/null || echo "")
GREEN=$(tput setaf 2 2>/dev/null || echo "")
YELLOW=$(tput setaf 3 2>/dev/null || echo "")
BLUE=$(tput setaf 4 2>/dev/null || echo "")
CYAN=$(tput setaf 6 2>/dev/null || echo "")
BOLD=$(tput bold 2>/dev/null || echo "")
RESET=$(tput sgr0 2>/dev/null || echo "")

need_cmd() {
	command -v "$1" >/dev/null 2>&1 || {
		echo "${RED}错误: 缺少命令 $1${RESET}" >&2
		exit 1
	}
}

need_cmd nmcli
need_cmd ip

clear
echo
echo "${BOLD}${CYAN}===============================================================${RESET}"
echo "${BOLD}${CYAN}                                                               ${RESET}"
echo "${BOLD}${CYAN}         Bond 网卡绑定配置工具 v2.0                              ${RESET}"
echo "${BOLD}${CYAN}         	自动化网络配置            	                         ${RESET}"
echo "${BOLD}${CYAN}                                                               ${RESET}"
echo "${BOLD}${CYAN}===============================================================${RESET}"
echo

mapfile -t IFACES < <(
	nmcli -t -f DEVICE,TYPE device status |
		awk -F: '
    $2=="ethernet" || $2=="infiniband" {
      dev=$1
      if (dev!="lo" && dev!~/(^bond|^br|^virbr|^docker|^veth|^tun|^tap|^wg|^sit|^gre|^vlan|^team)/) print dev
    }'
)

if ((${#IFACES[@]} < 2)); then
	echo "${RED}错误: 可用物理网卡少于 2 块, 无法创建 bond${RESET}"
	nmcli device status
	exit 1
fi

echo "${BOLD}${BLUE}---------------------------------------------------------------${RESET}"
echo "${BOLD}${BLUE} 可用物理网卡列表                                             ${RESET}"
echo "${BOLD}${BLUE}---------------------------------------------------------------${RESET}"
echo
for i in "${!IFACES[@]}"; do
	dev="${IFACES[$i]}"
	state=$(nmcli -t -f DEVICE,STATE device status | awk -F: -v d="$dev" '$1==d{print $2}')
	mac=$(nmcli -t -f GENERAL.HWADDR device show "$dev" 2>/dev/null | cut -d: -f2- || echo "unknown")
	ip4=$(ip -4 -o addr show "$dev" 2>/dev/null | awk '{print $4}' | head -n1 || echo "none")
	printf "  ${BOLD}${YELLOW}[%d]${RESET} ${CYAN}%-12s${RESET}  状态: ${GREEN}%-12s${RESET}  IP: ${YELLOW}%-18s${RESET}  MAC: ${BLUE}%s${RESET}\n" "$i" "$dev" "$state" "${ip4}" "${mac}"
done
echo

echo "${BOLD}${BLUE}---------------------------------------------------------------${RESET}"
echo "${BOLD}${BLUE} Bond 基本配置                                                ${RESET}"
echo "${BOLD}${BLUE}---------------------------------------------------------------${RESET}"
echo
read -rp "  ${BOLD}Bond 接口名称${RESET} (默认 bond0): " BOND_NAME
BOND_NAME="${BOND_NAME:-bond0}"
echo

echo "${BOLD}${BLUE}---------------------------------------------------------------${RESET}"
echo "${BOLD}${BLUE} Bond 工作模式选择                                            ${RESET}"
echo "${BOLD}${BLUE}---------------------------------------------------------------${RESET}"
echo
echo "  ${YELLOW}0)${RESET} balance-rr      (轮询模式)"
echo "  ${YELLOW}1)${RESET} active-backup   (主备模式) ${GREEN}推荐${RESET}"
echo "  ${YELLOW}2)${RESET} balance-xor     (XOR 哈希分流)"
echo "  ${YELLOW}3)${RESET} broadcast       (广播模式)"
echo "  ${YELLOW}4)${RESET} 802.3ad (LACP)  (动态链路聚合)"
echo "  ${YELLOW}5)${RESET} balance-tlb     (发送负载均衡)"
echo "  ${YELLOW}6)${RESET} balance-alb     (发送+接收负载均衡) ${GREEN}生产推荐${RESET}"
echo
read -rp "  ${BOLD}请选择模式${RESET} (默认 6): " MODE_NO
MODE_NO="${MODE_NO:-6}"

case "$MODE_NO" in
0) BOND_MODE="balance-rr" ;;
1) BOND_MODE="active-backup" ;;
2) BOND_MODE="balance-xor" ;;
3) BOND_MODE="broadcast" ;;
4) BOND_MODE="802.3ad" ;;
5) BOND_MODE="balance-tlb" ;;
6) BOND_MODE="balance-alb" ;;
*)
	echo "${RED}无效的模式选择${RESET}"
	exit 1
	;;
esac
echo

echo "${BOLD}${BLUE}---------------------------------------------------------------${RESET}"
echo "${BOLD}${BLUE} IPv4 配置方式                                                ${RESET}"
echo "${BOLD}${BLUE}---------------------------------------------------------------${RESET}"
echo
echo "  ${YELLOW}1)${RESET} DHCP (自动获取) ${GREEN}默认${RESET}"
echo "  ${YELLOW}2)${RESET} 静态 IP (手动指定)"
echo
read -rp "  ${BOLD}请选择配置方式${RESET} (默认 1): " IP_MODE
IP_MODE="${IP_MODE:-1}"

ADDR_CIDR=""
GATEWAY=""
DNS_SERVERS=""

if [[ "$IP_MODE" == "2" ]]; then
	IP_METHOD="manual"
	echo
	read -rp "  IPv4 地址 (如 192.168.1.100): " IPADDR
	read -rp "  子网前缀 (默认 24): " PREFIX
	PREFIX="${PREFIX:-24}"
	ADDR_CIDR="${IPADDR}/${PREFIX}"

	read -rp "  配置默认网关? (y/N): " GW_YN
	if [[ "$GW_YN" =~ ^[Yy]$ ]]; then
		read -rp "    网关地址: " GATEWAY
	fi

	read -rp "  配置 DNS? (y/N): " DNS_YN
	if [[ "$DNS_YN" =~ ^[Yy]$ ]]; then
		read -rp "    DNS 服务器 (多个用逗号分隔): " DNS_SERVERS
	fi
else
	IP_METHOD="auto"
fi
echo

echo "${BOLD}${BLUE}---------------------------------------------------------------${RESET}"
echo "${BOLD}${BLUE} 选择网卡 (至少 2 块)                                        ${RESET}"
echo "${BOLD}${BLUE}---------------------------------------------------------------${RESET}"
echo
read -rp "  ${BOLD}输入网卡序号${RESET} (用空格分隔, 如: 0 1): " -a IDX

if ((${#IDX[@]} < 2)); then
	echo "${RED}错误: 至少需要选择 2 块网卡${RESET}"
	exit 1
fi

SLAVES=()
for id in "${IDX[@]}"; do
	if ! [[ "$id" =~ ^[0-9]+$ ]] || ((id >= ${#IFACES[@]})); then
		echo "${RED}错误: 无效序号 $id${RESET}"
		exit 1
	fi
	SLAVES+=("${IFACES[$id]}")
done

echo
echo "${BOLD}${GREEN}===============================================================${RESET}"
echo "${BOLD}${GREEN} 配置预览                                                     ${RESET}"
echo "${BOLD}${GREEN}===============================================================${RESET}"
printf "  ${BOLD}Bond 接口名${RESET} : ${YELLOW}%s${RESET}\n" "$BOND_NAME"
printf "  ${BOLD}工作模式${RESET}    : ${YELLOW}%s${RESET}\n" "$BOND_MODE"
printf "  ${BOLD}IPv4 配置${RESET}   : ${YELLOW}%s${RESET}\n" "$([ "$IP_METHOD" = "auto" ] && echo "DHCP (自动获取)" || echo "静态 IP: $ADDR_CIDR")"
if [ "$IP_METHOD" = "manual" ]; then
	[[ -n "$GATEWAY" ]] && printf "  ${BOLD}默认网关${RESET}    : ${YELLOW}%s${RESET}\n" "$GATEWAY"
	[[ -n "$DNS_SERVERS" ]] && printf "  ${BOLD}DNS 服务器${RESET}  : ${YELLOW}%s${RESET}\n" "$DNS_SERVERS"
fi
printf "  ${BOLD}Slave 网卡${RESET}  : ${YELLOW}%s${RESET}\n" "${SLAVES[*]}"
echo "${BOLD}${GREEN}===============================================================${RESET}"
echo

read -rp "${BOLD}${YELLOW}确认开始配置? (y/N): ${RESET}" OK
if [[ ! "$OK" =~ ^[Yy]$ ]]; then
	echo "${YELLOW}已取消操作${RESET}"
	exit 0
fi

echo
echo "${BOLD}${CYAN}===============================================================${RESET}"
echo "${BOLD}${CYAN} 正在配置 Bond 接口...                                        ${RESET}"
echo "${BOLD}${CYAN}===============================================================${RESET}"
echo

nmcli connection down "$BOND_NAME" 2>/dev/null || true
nmcli connection delete "$BOND_NAME" 2>/dev/null || true
for dev in "${SLAVES[@]}"; do
	nmcli connection delete "${BOND_NAME}-slave-${dev}" 2>/dev/null || true
	nmcli connection delete "Wired connection $dev" 2>/dev/null || true
	nmcli device disconnect "$dev" 2>/dev/null || true
done
sleep 1

echo "  创建 Bond 接口 ${YELLOW}$BOND_NAME${RESET} (模式: ${YELLOW}$BOND_MODE${RESET})"
nmcli connection add type bond con-name "$BOND_NAME" ifname "$BOND_NAME" \
	ipv4.method auto ipv6.method ignore connection.autoconnect yes >/dev/null

nmcli connection modify "$BOND_NAME" bond.options "mode=$BOND_MODE,miimon=100"

if [ "$IP_METHOD" = "manual" ]; then
	echo "  配置静态 IP: ${YELLOW}$ADDR_CIDR${RESET}"
	nmcli connection modify "$BOND_NAME" ipv4.method "$IP_METHOD" ipv4.addresses "$ADDR_CIDR"
	[[ -n "$GATEWAY" ]] && nmcli connection modify "$BOND_NAME" ipv4.gateway "$GATEWAY"
	[[ -n "$DNS_SERVERS" ]] && nmcli connection modify "$BOND_NAME" ipv4.dns "${DNS_SERVERS//,/ }"
fi

for dev in "${SLAVES[@]}"; do
	slave_con="${BOND_NAME}-slave-${dev}"
	echo "  添加 slave 网卡: ${YELLOW}$dev${RESET}"
	nmcli connection add type bond-slave con-name "$slave_con" ifname "$dev" master "$BOND_NAME" connection.autoconnect yes >/dev/null
	nmcli connection up "$slave_con" >/dev/null
done

sleep 1

echo "  激活 Bond 接口..."
if ! nmcli connection up "$BOND_NAME"; then
	echo "${RED}激活失败! 请运行以下命令查看日志:${RESET}"
	echo "  ${YELLOW}journalctl -u NetworkManager -xe | grep -i $BOND_NAME${RESET}"
	exit 1
fi

sleep 2

echo
echo "${BOLD}${GREEN}===============================================================${RESET}"
echo "${BOLD}${GREEN} Bond 配置完成!                                               ${RESET}"
echo "${BOLD}${GREEN}===============================================================${RESET}"
echo

echo "${BOLD}${BLUE}当前网络状态:${RESET}"
echo "${BLUE}---------------------------------------------------------------${RESET}"
nmcli device status
echo

echo "${BOLD}${BLUE}Bond IP 地址:${RESET}"
echo "${BLUE}---------------------------------------------------------------${RESET}"
ip -4 addr show "$BOND_NAME" 2>/dev/null | grep inet || echo "  ${YELLOW}(DHCP 可能尚未分配)${RESET}"
echo

echo "${BOLD}${BLUE}Bond 详细信息:${RESET}"
echo "${BLUE}---------------------------------------------------------------${RESET}"
cat /proc/net/bonding/"$BOND_NAME" 2>/dev/null || ip -d link show "$BOND_NAME"

echo
echo "${BOLD}${GREEN}===============================================================${RESET}"
echo "${BOLD}${GREEN} 配置成功! 你可以完美操作了!                                 ${RESET}"
echo "${BOLD}${GREEN}===============================================================${RESET}"
echo

echo "${BOLD}${YELLOW}常用管理命令:${RESET}"
echo "${YELLOW}---------------------------------------------------------------${RESET}"
echo
echo "${BOLD}${CYAN}查看 Bond 状态:${RESET}"
echo "  cat /proc/net/bonding/${BOND_NAME}"
echo "  nmcli device status"
echo "  ip addr show ${BOND_NAME}"
echo
echo "${BOLD}${CYAN}删除 Bond 配置:${RESET}"
echo "  nmcli connection down ${BOND_NAME}"
echo "  nmcli connection delete ${BOND_NAME}"
for dev in "${SLAVES[@]}"; do
	echo "  nmcli connection delete ${BOND_NAME}-slave-${dev}"
done
echo
echo "${BOLD}${CYAN}重启 Bond:${RESET}"
echo "  nmcli connection down ${BOND_NAME} && nmcli connection up ${BOND_NAME}"
echo
echo "${YELLOW}---------------------------------------------------------------${RESET}"
echo
