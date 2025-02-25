# OpenWebUI Docker Config
## Description
This docker compose file is used to deploy the OpenWebUI application. It contains the following services:
- OpenWebUI: The main application
- Nginx: Reverse proxy for the OpenWebUI application
- Certbot: SSL certificate management
- Watchtower: Automatic updates for the OpenWebUI application

## Usage
1. Clone the repository
2. Create some directories:
    - `mkdir nginx/conf`
    - `mkdir nginx/logs`
    - `mkdir certbot/conf`
    - `mkdir certbot/www`
3. Move the ngix.conf file to the `nginx/conf` directory
4. Run the following command:
    - `docker-compose up -d`
5. Access the OpenWebUI application at `https://<your_domain>`
