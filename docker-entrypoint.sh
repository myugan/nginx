#!/bin/bash

# Docker entrypoint script for Nginx reverse proxy with SSL support
#
# This script sets up and manages an Nginx reverse proxy with automatic SSL certificate
# generation and renewal using Certbot and Cloudflare DNS authentication. It supports
# both local development and production environments.
#
# Features:
# - Automatic SSL certificate generation and renewal
# - Nginx configuration setup and management
# - Service readiness check
# - Local and production mode support
# - Cloudflare DNS integration for SSL challenges
# - Custom user creation support
# - Automatic Nginx configuration updates
#
# Usage: ./docker-entrypoint.sh [OPTION]
# Options:
#   --help       Show help message
#   reload       Reload Nginx configuration
#   renew        Generate or renew SSL certificate
#   reconfigure  Regenerate Nginx configuration from template and reload if changed
#   (none)       Start the normal process
#
# Environment variables:
#   Required: FQDN, SERVICE_NAME, SERVICE_PORT
#   Required for production: CERTBOT_EMAIL, CERTBOT_DOMAIN, CLOUDFLARE_EMAIL, CLOUDFLARE_API_KEY
#   Optional: LOCAL (default: false), RENEWAL_INTERVAL (default: 3d)
#   Optional: NGINX_TEMPLATE (default: /etc/nginx/conf.d/default.conf.template), NGINX_CONF (default: /etc/nginx/conf.d/default.conf)
#   Optional: CUSTOM_USER (default: false), CUSTOM_USERNAME, CUSTOM_UID
#   Optional: FLOATING_IP
#
# Notes:
# - In local mode, SSL certificate generation is skipped
# - The script uses watchexec to monitor template changes and automatically reconfigure Nginx
# - Certbot is used for SSL certificate management with Cloudflare DNS challenge
# - The script attempts to retrieve the public IP using ifconfig.me or ifconfig.co as a fallback

set -euo pipefail

CERT_RENEWAL_THRESHOLD=30
LOCAL=${LOCAL:-false}
RENEWAL_INTERVAL=${RENEWAL_INTERVAL:-3d}
NGINX_TEMPLATE=${NGINX_TEMPLATE:-"/etc/nginx/conf.d/default.conf.template"}
NGINX_CONF=${NGINX_CONF:-"/etc/nginx/conf.d/default.conf"}

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}$(date '+%Y-%m-%d %H:%M:%S')${NC} $1: $2"; }
log_error() { log "${RED}ERROR${NC}" "$1" >&2; }
log_info() { log "${GREEN}INFO${NC}" "$1"; }
log_warn() { log "${YELLOW}WARN${NC}" "$1"; }

check_required_vars() {
    local required_vars=("FQDN" "SERVICE_NAME" "SERVICE_PORT")
    
    # Add Cloudflare and Certbot variables only if LOCAL is not true
    if [[ "$LOCAL" != "true" ]]; then
        required_vars+=("CERTBOT_EMAIL" "CERTBOT_DOMAIN" "CLOUDFLARE_EMAIL" "CLOUDFLARE_API_KEY")
    fi

    local missing_vars=()

    for var in "${required_vars[@]}"; do
        [ -z "${!var+x}" ] || [ -z "${!var}" ] && missing_vars+=("$var")
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required variables: ${missing_vars[*]}"
        exit 1
    fi

    # Log info about mode
    if [[ "$LOCAL" == "true" ]]; then
        log_info "Running in local mode. Skipping Cloudflare and Certbot checks."
        log_info "Add '127.0.0.1 $FQDN' to your /etc/hosts file for local access."
    else
        log_info "Running in production mode. Cloudflare and Certbot checks will be performed."
    fi
}

setup_cloudflare_ini() {
    [[ ! -f "/etc/cloudflare.ini" ]] && {
        echo "dns_cloudflare_email = $CLOUDFLARE_EMAIL" > /etc/cloudflare.ini
        echo "dns_cloudflare_api_key = $CLOUDFLARE_API_KEY" >> /etc/cloudflare.ini
        chmod 600 /etc/cloudflare.ini
    }
}

verify_domain_ip() {
    local expected_ip
    local actual_ip
    
    if [ -n "${FLOATING_IP:-}" ]; then
        expected_ip="$FLOATING_IP"
        log_info "Using FLOATING_IP: $expected_ip"
    else
        # Try ifconfig.me first, then fall back to ifconfig.co if it fails
        expected_ip=$(curl -s -m 5 ifconfig.me) || expected_ip=$(curl -s -m 5 ifconfig.co)
        
        if [ -z "$expected_ip" ]; then
            log_error "Failed to retrieve public IP address. Please check your internet connection."
            return 1
        fi
        log_info "Using public IP: $expected_ip"
    fi
    
    # Use dig to get the IP address associated with the FQDN
    actual_ip=$(dig +short "$FQDN")

    log_info "Verifying domain IP..."
    log_info "Expected IP: $expected_ip"
    log_info "Actual IP (DNS): $actual_ip"

    if [ "$expected_ip" = "$actual_ip" ]; then
        log_info "Domain IP verification successful: $FQDN -> $actual_ip"
        return 0
    else
        log_error "Domain IP mismatch: $FQDN -> $actual_ip (expected $expected_ip)"
        return 1
    fi
}

check_renewal_config() {
    local config_file="/etc/letsencrypt/renewal/$FQDN.conf"
    if [ ! -f "$config_file" ]; then
        log_info "Renewal config not found for $FQDN"
        return 1
    fi

    if grep -q "authenticator = dns-cloudflare" "$config_file"; then
        log_info "Renewal config found for $FQDN"
        return 0
    else
        rm -f "$config_file"
        log_info "Removed invalid renewal config for $FQDN"
        return 1
    fi
}

generate_cert() {
    log_info "Generating new certificate..."
    setup_cloudflare_ini
    check_renewal_config

    if verify_domain_ip; then
        if certbot certonly -n --agree-tos -m "$CERTBOT_EMAIL" --dns-cloudflare --dns-cloudflare-credentials /etc/cloudflare.ini --preferred-challenges dns-01 -d "$CERTBOT_DOMAIN"; then
            log_info "Certificate generated successfully."
        else
            log_error "Failed to generate certificate. Check Certbot logs."
            return 1
        fi
    else
        log_error "Domain IP verification failed. Please ensure $FQDN points to $(curl -s ifconfig.me) in your DNS settings."
        return 1
    fi
}

renew_cert() {
    log_info "Renewing certificate..."
    setup_cloudflare_ini
    check_renewal_config

    if certbot renew --force-renewal --dns-cloudflare --dns-cloudflare-credentials /etc/cloudflare.ini --preferred-challenges dns-01; then
        log_info "Certificate renewed successfully."
        reload_nginx
    else
        log_error "Failed to renew certificate. Check Certbot logs."
        return 1
    fi
}

autorenew_cert() {
    log_info "Starting certificate auto-renewal process..."
    while true; do
        check_cert
        sleep $RENEWAL_INTERVAL
    done
}

check_cert() {
    local cert_path="/etc/letsencrypt/live/$CERTBOT_DOMAIN/cert.pem"

    if [[ ! -f "$cert_path" ]]; then
        generate_cert
    else
        local days_until_expiry=$(( ($(date -d "$(openssl x509 -in "$cert_path" -noout -enddate | cut -d= -f2)" +%s) - $(date +%s)) / 86400 ))
        if [[ $days_until_expiry -le $CERT_RENEWAL_THRESHOLD ]]; then
            log_warn "Certificate expires in $days_until_expiry days. Renewing..."
            renew_cert
        else
            log_info "Certificate valid for $days_until_expiry days. Skipping renewal."
        fi
    fi
}

check_nginx_config() {
    log_info "Checking Nginx configuration..."
    if nginx -t; then
        log_info "Nginx configuration is valid."
        return 0
    else
        log_error "Invalid Nginx configuration. Check logs and settings."
        return 1
    fi
}

create_custom_user() {
    CUSTOM_USER=${CUSTOM_USER:-"false"}
    CUSTOM_USERNAME=${CUSTOM_USERNAME:-""}
    CUSTOM_UID=${CUSTOM_UID:-""}

    if [[ "$CUSTOM_USER" == "true" ]]; then
        if [[ -z "$CUSTOM_USERNAME" || -z "$CUSTOM_UID" ]]; then
            log_error "CUSTOM_USERNAME and CUSTOM_UID must be set when CUSTOM_USER is true"
            exit 1
        fi

        if ! id "$CUSTOM_USERNAME" &>/dev/null; then
            useradd -u $CUSTOM_UID -U $CUSTOM_USERNAME
            log_info "Custom user $CUSTOM_USERNAME created with UID $CUSTOM_UID"
        else
            log_info "User $CUSTOM_USERNAME already exists, skipping creation"
        fi
    else
        log_info "CUSTOM_USER is not set to 'true', skipping custom user creation"
    fi
}

setup_nginx() {
    create_custom_user

    if [[ ! -f "$NGINX_TEMPLATE" ]]; then
        log_error "Nginx configuration template not found at: $NGINX_TEMPLATE"
        log_error "Please ensure the template file exists and is accessible."
        exit 1
    fi

    log_info "Generating Nginx configuration..."
    envsubst '${FQDN} ${SERVICE_NAME} ${SERVICE_PORT}' < "$NGINX_TEMPLATE" > "$NGINX_CONF"

    if ! check_nginx_config; then
        exit 1
    fi
}

start_nginx() {
    if pgrep -x "nginx" > /dev/null; then
        log_info "Nginx is already running."
    else
        log_info "Starting Nginx..."
        if nginx -g 'daemon off;'; then
            log_info "Nginx started successfully."
        else
            log_error "Failed to start Nginx. Check logs for details."
            return 1
        fi
    fi
}

reload_nginx() {
    log_info "Reloading Nginx..."
    if output=$(nginx -s reload 2>&1); then
        log_info "Nginx reloaded successfully."
    else
        log_error "Failed to reload Nginx. Error: $output"
    fi
}

update_and_reload_nginx() {
    create_custom_user

    if setup_nginx; then
        log_info "Nginx configuration updated successfully. Reloading..."
        reload_nginx
    else
        log_error "Failed to update Nginx configuration. Not reloading."
    fi
}

wait_for_service() {
    log_info "Waiting for $SERVICE_NAME to be ready on port $SERVICE_PORT..."
    local max_attempts=30
    local attempt=1

    while ! timeout 1 bash -c "echo > /dev/tcp/$SERVICE_NAME/$SERVICE_PORT" >/dev/null 2>&1; do
        if [ $attempt -ge $max_attempts ]; then
            log_error "Service $SERVICE_NAME not ready after $max_attempts attempts. Exiting."
            exit 1
        fi
        log_warn "Attempt $attempt: $SERVICE_NAME is not ready. Retrying in 5 seconds..."
        sleep 5
        ((attempt++))
    done

    log_info "$SERVICE_NAME is ready on port $SERVICE_PORT."
}

show_help() {
    echo "Usage: $0 [OPTION]"
    echo "Options:"
    echo "  --help       Show this help message"
    echo "  reload       Reload Nginx configuration"
    echo "  renew        Generate or renew SSL certificate"
    echo "  reconfigure  Regenerate Nginx configuration from template and reload if changed"
    echo "  (none)       Start the normal process"
}

main() {
    if [ $# -gt 0 ]; then
        case "$1" in
            --help|-h)
                show_help
                exit 0
                ;;
            reload)
                reload_nginx
                exit $?
                ;;
            renew)
                renew_cert
                exit $?
                ;;
            reconfigure)
                update_and_reload_nginx
                exit $?
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    fi

    check_required_vars
    wait_for_service

    if [[ "$LOCAL" == "true" ]]; then
        if setup_nginx; then
            start_nginx &
            NGINX_PID=$!
            log_info "Local setup completed. Waiting for Nginx process..."
            watchexec -w "$NGINX_TEMPLATE" $0 reconfigure &
            WATCHEXEC_PID=$!
            wait $NGINX_PID $WATCHEXEC_PID
        else
            log_error "Local setup failed. Check logs."
            exit 1
        fi
    else
        if check_cert && setup_nginx; then
            start_nginx &
            NGINX_PID=$!
            autorenew_cert &
            AUTORENEW_PID=$!
            log_info "Setup completed. Waiting for processes to finish..."
            watchexec -w "$NGINX_TEMPLATE" $0 reconfigure &
            WATCHEXEC_PID=$!
            wait $NGINX_PID $AUTORENEW_PID $WATCHEXEC_PID
        else
            log_error "Setup failed. Check logs."
            exit 1
        fi
    fi
}

main "$@"