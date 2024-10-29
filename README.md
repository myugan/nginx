# Nginx

<div align="center">

Automated Nginx reverse proxy with Certbot SSL management

[![GitHub stars](https://img.shields.io/github/stars/myugan/nginx.svg)](https://github.com/myugan/nginx/stargazers)
[![GitHub issues](https://img.shields.io/github/issues/myugan/nginx.svg)](https://github.com/myugan/nginx/issues)
[![GitHub license](https://img.shields.io/github/license/myugan/nginx.svg)](https://github.com/myugan/nginx/blob/master/LICENSE)

</div>

## Overview

A containerized Nginx with automatic SSL certificate management. It handles both development and production environments with minimal configuration.

### Features

- ✨ Automatic SSL certificate generation and renewal
- 🛡️ Cloudflare DNS integration
- 🚀 Development & production modes
- 📝 Dynamic configuration templates

## Usage

### Basic Example

```bash
# Development
export LOCAL=true FQDN=demo.local SERVICE_NAME=httpbin SERVICE_PORT=80
docker-compose -f local.yml up --build

# Production
export FQDN=example.com CERTBOT_EMAIL=admin@example.com
docker-compose -f production.yml up --build
```

### Environment Variables

<details>
<summary>Click to expand environment variables</summary>

| Variable | Description | Required in Local | Required in Production |
|----------|-------------|:-----------------:|:----------------------:|
| LOCAL | Set to "true" for local setup | ✅ | ❌ |
| FQDN | Your domain name | ✅ | ✅ |
| SERVICE_NAME | Name of the service to proxy | ✅ | ✅ |
| SERVICE_PORT | Port of the service to proxy | ✅ | ✅ |
| CERTBOT_EMAIL | Email for Let's Encrypt | ❌ | ✅ |
| CERTBOT_DOMAIN | Domain for SSL certificate | ❌ | ✅ |
| CLOUDFLARE_EMAIL | Cloudflare account email | ❌ | ✅ |
| CLOUDFLARE_API_KEY | Cloudflare API key | ❌ | ✅ |
| RENEWAL_INTERVAL | Certificate renewal check interval (default: 3d) | ❌ | ✅ |
| NGINX_TEMPLATE | Path to Nginx config template (default: /etc/nginx/conf.d/default.conf.template) | ❌ | ❌ |
| NGINX_CONF | Path to generated Nginx config (default: /etc/nginx/conf.d/default.conf) | ❌ | ❌ |
| CUSTOM_USER | Set to "true" to create a custom user (default: false) | ❌ | ❌ |
| CUSTOM_USERNAME | Username for custom user (required if CUSTOM_USER is true) | ❌ | ❌ |
| CUSTOM_UID | UID for custom user (required if CUSTOM_USER is true) | ❌ | ❌ |
| FLOATING_IP | IP address to use for domain verification (optional) | ❌ | ❌ |

</details>

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.