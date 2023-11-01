## auto-cert-manager

![Docker Pulls](https://img.shields.io/docker/pulls/rehanone/auto-cert-manager) ![GitHub release (with filter)](https://img.shields.io/github/v/release/rehanone/auto-cert-manager)

---

This image runs [`certbot`](https://certbot.eff.org/) under the hood to automate issuance and renewal of letsencrypt certificates.

Initial certificate requests are run at container first launch, using DNS-01 challenge. Currently it supports the following plugins:

  - cloudfare
  - linode

Then certificates validity is checked at 02:00 on every 7th day-of-month from 1 through 31, and certificates are renewed only if expiring in less that 28 days, preventing from being rate limited by letsencrypt.

Issued certificates are made available in the container's `/certs` directory which can be mounted on the docker host or as a docker volume to make them available to other applications.

### Requirements

- docker
- docker-compose

### Configure the image's run parameters
 Adapt the provided `docker-compose.yml` file to fit your requirements. The required/optional parameters are described here after:

#### Build or fetch the docker image

- Either build image with provided docker file
- Or fetch the image from dockerhub located at [`rehanone/auto-cert-manager`](https://hub.docker.com/repository/docker/rehanone/auto-cert-manager#)

#### Ports
No port mapping required as this image uses dns-01 challenge.

#### Volumes
The following volumes of interest can be mounted on the docker host or as docker volumes:
- **/certs** : location of certificates generated by letsencrypt, this is the main directory of interest to expose to your application
- **/etc/letsencrypt** : location of letsencrypt install dir (optional, for debug purposes)
- **/var/log/letsencrypt** : location of letsencrypt logs (optional, for debug purposes)

#### Environment variables:

Setting                  | Type     |  Description
------------------------ | -------- | ---------------------------------
**DOMAINS**              | required | Space separated list of comma separated subdomains to register the certificate with, for example: [`my.domain.com`, `sub.domain1.com,sub.domain2.com`, `my.other.domain.com sub.domain1.com,sub.domain2.com`]
**EMAIL**                | required | Email of the certificates supplicant
**CERTBOT_PLUGIN**       | required | Supported values are (`cloudflare`, `linode`)
**CLOUDFLARE_API_TOKEN/CLOUDFLARE_API_TOKEN_FILE** | required when **CERTBOT_PLUGIN=cloudflare** | Cloudflare API credentials, obtained from your [Cloudflare dashboard](https://dash.cloudflare.com/profile).
**LINODE_API_KEY/LINODE_API_KEY_FILE**       | required when **CERTBOT_PLUGIN=linode** | Linode API credentials, obtained from your Linode account’s [Applications & API Tokens page](https://cloud.linode.com/profile/tokens).
**LINODE_API_VERSION**   | optional when **CERTBOT_PLUGIN=linode** | Linode API version, normally can be left blank.
**PROPAGATION_SECONDS**  | optional | The number of seconds to wait for DNS to propagate before asking the ACME server to verify the DNS record. (Default: dependent on plugin).
**DEBUG**                | optional | whether to run letsencrypt in debug mode, refer to certbot [documentation](https://certbot.eff.org/docs/using.html#certbot-command-line-options)
**LOGFILE**              | optional | path of a file where to write the logs from the certificate request/renewal script. When not provided both stdout/stderr are directed to console which is convenient when using a docker log driver.
**STAGING**              | optional | whether to run letsencrypt in staging mode, refer to certbot [documentation](https://certbot.eff.org/docs/using.html#certbot-command-line-options)
**CONCAT**               | optional | whether to concatenate the full chain of the certificate authority with the certificate's private key. This is required for example for haproxy. Otherwise the full chain and private key are kept in separate files which is required for example for nginx and apache.
**PKCS12_ENABLE**        | optional | Enables PKCS#12 certificate convertion. The final certificate will be in */certs/{domain}.pfx* file.
**PKCS12_PASSWORD/PKCS12_PASSWORD_FILE** | optional when **PKCS12_ENABLE=true** | Enables PKCS#12 certificate convertion. The final certificate will be in */certs/{domain}.pfx* file.

#### Example
As in the provided `docker-compose.yml` file, the expected configuration should look similar to this:

```yml
---
version: '3.8'

secrets:
  pkcs12_password:
    file: secrets/pkcs12_password
  cf_token:
    file: secrets/cf_token

services:
  certbot:
    build: .
    container_name: certbot
    secrets:
      - pkcs12_password
    volumes:
      - ./certs:/certs
      - ./letsencrypt:/etc/letsencrypt
      - ./log:/var/log/letsencrypt
    environment:
      - DOMAINS=my.domain.com
      - EMAIL=user@my.domain.com
      - CERTBOT_PLUGIN=linode
      - LINODE_API_KEY=your_api_key
      - LINODE_API_VERSION=
      - CLOUDFLARE_API_TOKEN=/run/secrets/cf_token
      - PROPAGATION_SECONDS=220
      - DEBUG=true
      - STAGING=true
      - CONCAT=false
      - PKCS12_ENABLE=true
      - PKCS12_PASSWORD_FILE=/run/secrets/pkcs12_password
    restart: unless-stopped
```

### Docker Logs
When using a docker logging driver, the `LOGFILE` environment variable should not be set to make sure all the container logs (stdout/stderr) are directed to the console, and hence to the logging driver.

### Build / run the container

#### Building
Build and run the container as follows:
```sh
docker-compose build
docker-compose up -d
```

#### Running image from dockerhub
```sh
docker-compose up -d
```
