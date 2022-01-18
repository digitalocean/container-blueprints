#!/usr/bin/env bash

set -eu -o pipefail

NEED_SERVER_RESTART="false"
CADDYFILE="/root/Caddyfile"
DOCKER_COMPOSE_FILE="/root/docker-compose.yml"

function print_warn() {
    local MESSAGE="$1"

    local YELLOW='\033[0;33m'
    local CLEAR='\033[0m'

    echo -e "${YELLOW}[WARNING]${CLEAR} $MESSAGE"
}

function print_info() {
    local MESSAGE="$1"

    local GREEN='\033[0;32m'
    local CLEAR='\033[0m'

    echo -e "${GREEN}[INFO]${CLEAR} $MESSAGE"
}

function print_error() {
    local MESSAGE="$1"

    local RED='\033[0;31m'
    local CLEAR='\033[0m'

    echo -e "${RED}[ERROR]${CLEAR} $MESSAGE"
}

function print_banner() {
    local MESSAGE="$1"

    echo
    echo "#########################################################################################"
    echo "#                                                                                       #"
    echo "#                                                                                       #"
    echo "# $MESSAGE     #"
    echo "#                                                                                       #"
    echo "#                                                                                       #"
    echo "#########################################################################################"
    echo
}

function stop_netmaker_server() {
    print_info "Stopping Netmaker server..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" down
}

function start_netmaker_server() {
    print_info "Starting Netmaker server..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" up -d
}

function restart_netmaker_server() {
    stop_netmaker_server
    start_netmaker_server
}

function set_anchor_ip_default_gw() {
    local SERVER_NETPLAN_FILE="/etc/netplan/50-cloud-init.yaml"

    local PUBLIC_INTERFACE_GW_IP_ADDRESS
    local SERVER_ANCHOR_IP_GW
    PUBLIC_INTERFACE_GW_IP_ADDRESS="$(curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/gateway)"
    SERVER_ANCHOR_IP_GW=$(curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/anchor_ipv4/gateway)

    if [[ "${SERVER_ANCHOR_IP_GW}null" == "null" ]]; then
        print_error "Server anchor IP gateway address cannnot be empty!"
        exit 1
    fi

    # Set default route for running session
    if ! ip route show default | grep "$SERVER_ANCHOR_IP_GW" &> /dev/null; then
        print_info "Setting default route for the current session to use anchor IP Gateway address: $SERVER_ANCHOR_IP_GW"
        ip route change default via "$SERVER_ANCHOR_IP_GW" dev eth0
    fi

    if [[ ! -f "$SERVER_NETPLAN_FILE" ]]; then
        print_warn "Could not find server netplan configuration file: $SERVER_NETPLAN_FILE!"
        print_warn "Default GW settings won't be persisted if machine reboots!"
        return 0
    fi
    
    if grep "$SERVER_ANCHOR_IP_GW" "$SERVER_NETPLAN_FILE" &> /dev/null; then
        print_warn "Netplan file: $SERVER_NETPLAN_FILE already contains an anchor IP GW configuration for this server, skipping!"
        return 0
    fi

    # First, backup files that we're going to change
    print_info "Backing up $SERVER_NETPLAN_FILE to ${SERVER_NETPLAN_FILE}.bk"
    cp "$SERVER_NETPLAN_FILE" "${SERVER_NETPLAN_FILE}.bk"
    
    # Persist settings across machine reboots
    print_info "Setting persistent settings for anchor IP Gateway address: ${SERVER_ANCHOR_IP_GW} in ${SERVER_NETPLAN_FILE}..."
    sed -i "s/gateway4:.*$PUBLIC_INTERFACE_GW_IP_ADDRESS/gateway4: $SERVER_ANCHOR_IP_GW/g" "$SERVER_NETPLAN_FILE"
    netplan apply -debug
}

function apply_caddyfile_changes() {
    local DROPLET_PUBLIC_IP_ADDRESS="$1"
    local DROPLET_FLOATING_IP_ADDRESS="$2"

    local FLOATING_IP_NETMAKER_BASE_DOMAIN
    local PUBLIC_NETMAKER_BASE_DOMAIN
    FLOATING_IP_NETMAKER_BASE_DOMAIN="nm.$(echo $DROPLET_FLOATING_IP_ADDRESS | tr . -).nip.io"
    PUBLIC_NETMAKER_BASE_DOMAIN="nm.$(echo $DROPLET_PUBLIC_IP_ADDRESS | tr . -).nip.io"

    if grep "$FLOATING_IP_NETMAKER_BASE_DOMAIN" "$CADDYFILE" &> /dev/null; then
        print_warn "Netmaker Caddy configuration file: ${CADDYFILE} already contains a Floating IP configuration for this server, skipping!"
        return 0
    fi

    print_info "Backing up Netmaker server Caddy file to: ${CADDYFILE}.bk..."
    cp "$CADDYFILE" "${CADDYFILE}.bk"
    print_info "Setting up Netmaker server Caddy configuration file to use Floating IP address: ${DROPLET_FLOATING_IP_ADDRESS}..."
    sed -i "s/$PUBLIC_NETMAKER_BASE_DOMAIN/$FLOATING_IP_NETMAKER_BASE_DOMAIN/g" "$CADDYFILE"
    NEED_SERVER_RESTART="true"
}

function apply_docker_compose_changes() {
    local DROPLET_PUBLIC_IP_ADDRESS="$1"
    local DROPLET_FLOATING_IP_ADDRESS="$2"

    local FLOATING_IP_NETMAKER_BASE_DOMAIN
    local FLOATING_IP_COREDNS
    local PUBLIC_NETMAKER_BASE_DOMAIN
    FLOATING_IP_NETMAKER_BASE_DOMAIN="nm.$(echo $DROPLET_FLOATING_IP_ADDRESS | tr . -).nip.io"
    FLOATING_IP_COREDNS=$(ip route get 1 | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p')
    PUBLIC_NETMAKER_BASE_DOMAIN="nm.$(echo $DROPLET_PUBLIC_IP_ADDRESS | tr . -).nip.io"

    if grep "$FLOATING_IP_NETMAKER_BASE_DOMAIN" "$DOCKER_COMPOSE_FILE" &> /dev/null; then
        print_warn "Docker compose file already contains Floating IP configuration for this server, skipping!"
        return 0
    fi
    
    print_info "Backing up Netmaker server docker compose file to: ${DOCKER_COMPOSE_FILE}.bk..."
    cp "$DOCKER_COMPOSE_FILE" "${DOCKER_COMPOSE_FILE}.bk"

    print_info "Setting up Netmaker server docker-compose file to use Floating IP address: ${DROPLET_FLOATING_IP_ADDRESS}..."
    sed -i "s/$PUBLIC_NETMAKER_BASE_DOMAIN/$FLOATING_IP_NETMAKER_BASE_DOMAIN/g" "$DOCKER_COMPOSE_FILE"
    # Replace all occurences, except coredns
    sed -i "/${DROPLET_PUBLIC_IP_ADDRESS}:53/ ! s/$DROPLET_PUBLIC_IP_ADDRESS/$DROPLET_FLOATING_IP_ADDRESS/g" "$DOCKER_COMPOSE_FILE"
    # Replace coredns entries now
    sed -i "s/${DROPLET_PUBLIC_IP_ADDRESS}:53/${FLOATING_IP_COREDNS}:53/g" "$DOCKER_COMPOSE_FILE"
    NEED_SERVER_RESTART="true"
}

function netmaker_floating_ip_config() {
    local DROPLET_PUBLIC_IP_ADDRESS
    local DROPLET_FLOATING_IP_ADDRESS
    local FLOATING_IP_NETMAKER_BASE_DOMAIN
    DROPLET_PUBLIC_IP_ADDRESS="$(curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address)"
    DROPLET_FLOATING_IP_ADDRESS="$(curl -s http://169.254.169.254/metadata/v1/floating_ip/ipv4/ip_address)"
    FLOATING_IP_NETMAKER_BASE_DOMAIN="nm.$(echo $DROPLET_FLOATING_IP_ADDRESS | tr . -).nip.io"

    apply_caddyfile_changes "$DROPLET_PUBLIC_IP_ADDRESS" "$DROPLET_FLOATING_IP_ADDRESS"
    apply_docker_compose_changes "$DROPLET_PUBLIC_IP_ADDRESS" "$DROPLET_FLOATING_IP_ADDRESS"
    
    if [[ "$NEED_SERVER_RESTART" == "true" ]]; then
        print_info "Restarting Netmaker server for changes to take effect..."
        restart_netmaker_server
        NEED_SERVER_RESTART="false"
    fi

    print_banner "To access the dashboard, please visit: https://dashboard.$FLOATING_IP_NETMAKER_BASE_DOMAIN"
}

function check_script_prerequisites() {
    local SCRIPT_REQUIRES="cp grep ip docker-compose netplan sed"

    for CMD in $SCRIPT_REQUIRES; do
        echo -ne "\033[0;32m[INFO]\033[0m Checking if command '$CMD' is available... "
        command -v "$CMD" &> /dev/null || {
            echo -e "\033[0;31mFAIL!\033[0m"
            exit 1
        }
        echo -e "\033[0;32mOK!\033[0m"
    done

    echo
}

function main() {
    check_script_prerequisites
    set_anchor_ip_default_gw
    netmaker_floating_ip_config
}

main "$@"
