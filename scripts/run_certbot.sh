#!/bin/sh

#!/usr/bin/env bash

# boostrapped from https://github.com/janeczku/haproxy-acme-validation-plugin/blob/master/cert-renewal-haproxy.sh

logger_error() {
  if [ -n "${LOGFILE}" ]
  then
    echo "[error] ${1}" >> ${LOGFILE}
  fi
  # make sure the job redirects directly to stdout/stderr instead of a log file
  # this works well in docker combined with a docker logging driver
  >&2 echo "[error] ${1}" > /proc/1/fd/1 2>/proc/1/fd/2
}

logger_info() {
  if [ -n "${LOGFILE}" ]
  then
    echo "[info] ${1}" >> ${LOGFILE}
  else
    # make sure the job redirects directly to stdout/stderr instead of a log file
    # this works well in docker combined with a docker logging driver
    echo "[info] ${1}" > /proc/1/fd/1 2>/proc/1/fd/2
  fi
}

issueCertificate() {
  certbot_response=`certbot certonly --agree-tos --renew-by-default --non-interactive --max-log-backups 100 --email $EMAIL $CERTBOT_ARGS -d $1 2>&1`
  certbot_return_code=$?
  logger_info "${certbot_response}"
  return ${certbot_return_code}
}

copyCertificate() {
  local d=${CERT_DOMAIN%%,*} # in case of multi-host domains, use first name only

  # certs are copied to /certs directory
  if [ "$CONCAT" = true ]; then
   # concat the full chain with the private key (e.g. for haproxy)
   cat /etc/letsencrypt/live/$d/fullchain.pem /etc/letsencrypt/live/$d/privkey.pem > /certs/$d.pem
   logger_info "Certificates for $d concatenated and copied to /certs dir"
  else
   # keep full chain and private key in separate files (e.g. for nginx and apache)
   cp /etc/letsencrypt/live/$d/cert.pem /certs/$d.pem
   cp /etc/letsencrypt/live/$d/privkey.pem /certs/$d.key.pem
   cp /etc/letsencrypt/live/$d/chain.pem /certs/$d.chain.pem
   cp /etc/letsencrypt/live/$d/fullchain.pem /certs/$d.fullchain.pem
   logger_info "Certificates for $d and copied to /certs dir"
  fi
}

convertToPfxCertificate() {
  local domain=${CERT_DOMAIN%%,*} # in case of multi-host domains, use first name only

  # certs are copied to /certs directory
  if [ "$PKCS12_ENABLE" = true ]; then
    logger_info "Processing PKCS12 certfificate convertion for domain: ${domain}"
    openssl pkcs12 -export -out /certs/${domain}.pfx -inkey /etc/letsencrypt/live/${domain}/privkey.pem -in /etc/letsencrypt/live/${domain}/cert.pem -certfile /etc/letsencrypt/live/${domain}/chain.pem -passout pass:${PKCS12_PASSWORD}
    logger_info "pkcs#12 generated! at /certs/${domain}.pfx"
  fi
}

processCertificates() {
  # Get the certificate for the domain(s) CERT_DOMAIN (a comma separated list)
  # The certificate will be named after the first domain in the list
  # To work, the following variables must be set:
  # - CERT_DOMAIN : comma separated list of domains
  # - EMAIL
  # - CONCAT
  # - CERTBOT_ARGS

  local d=${CERT_DOMAIN%%,*} # in case of multi-host domains, use first name only

  if [ -d /etc/letsencrypt/live/$d ]; then
    cert_path=$(find /etc/letsencrypt/live/$d -name cert.pem -print0)
    if [ $cert_path ]; then
      # check for certificates expiring in less that 28 days
      if ! openssl x509 -noout -checkend $((4*7*86400)) -in "${cert_path}"; then
        subject="$(openssl x509 -noout -subject -in "${cert_path}" | grep -o -E 'CN=[^ ,]+' | tr -d 'CN=')"
        subjectaltnames="$(openssl x509 -noout -text -in "${cert_path}" | sed -n '/X509v3 Subject Alternative Name/{n;p}' | sed 's/\s//g' | tr -d 'DNS:' | sed 's/,/ /g')"
        domains="${subject}"

        # look for certificate additional domain names and append them as '-d <name>' (-d for certbot's --domains option)
        for altname in ${subjectaltnames}; do
          if [ "${altname}" != "${subject}" ]; then
            if [ "${domains}" != "" ]; then
              domains="${domains} -d ${altname}"
            else
              domains="${altname}"
            fi
          fi
        done

        # renewing certificate
        logger_info "Renewing certificate for $domains"
        issueCertificate "${domains}"

        if [ $? -ne 0 ]; then
          logger_error "Failed to renew certificate! check /var/log/letsencrypt/letsencrypt.log!"
          exitcode=1
        else
          logger_info "Renewed certificate for ${subject}"
          copyCertificate
          convertToPfxCertificate
        fi

      else
        logger_info "Certificate for $d does not require renewal"
      fi
    fi
  else
    # initial certificate request
    logger_info "Getting certificate for $CERT_DOMAIN"
    issueCertificate "${CERT_DOMAIN}"

    if [ $? -ne 0 ]; then
      logger_error "Failed to request certificate! check /var/log/letsencrypt/letsencrypt.log!"
      exitcode=1
    else
      logger_info "Certificate delivered for $CERT_DOMAIN"
      copyCertificate
      convertToPfxCertificate
    fi
  fi
}

generateCredentialsFile() {
  local certbotPlugin=${1}
  local credentialsFile=${2}

  if [ "$certbotPlugin" = "cloudflare" ]; then

    logger_info "Writing credentials file template for ${certbotPlugin}"

    # Generate cloudflare credentials file
    cat > $credentialsFile << EOL
dns_cloudflare_api_token = ${CLOUDFLARE_API_TOKEN}
EOL

  fi

  if [ "$certbotPlugin" = "linode" ]; then

    logger_info "Writing credentials file template for ${certbotPlugin}"

    # Generate linode credentials file
    cat > $credentialsFile << EOL
dns_linode_key = ${LINODE_API_KEY}
dns_linode_version = ${LINODE_API_VERSION}
EOL

  fi
}

## ================================== MAIN ================================== ##

# bootstrap a list of optional arguments for certbot
CERTBOT_ARGS=""


_main() {

  local credentialsFile="/credentials/dns-creds.ini"

  # Generate credentials file
  generateCredentialsFile "${CERTBOT_PLUGIN}" "${credentialsFile}"

  local pluginArgs=""

  if [ "$CERTBOT_PLUGIN" = "cloudflare" ]; then
    ##
    # Trigger certbot's dns-cloudflare plugin
    #
    # The dns_linode plugin automates the process of completing a dns-01 challenge (DNS01) by creating, 
    # and subsequently removing, TXT records using the Linode API.
    # see https://certbot-dns-linode.readthedocs.io/en/stable/
    #
    pluginArgs="--dns-cloudflare --dns-cloudflare-credentials ${credentialsFile}"
    if [ ! -z "${PROPAGATION_SECONDS}" ]; then
      pluginArgs="${pluginArgs} --dns-cloudflare-propagation-seconds ${PROPAGATION_SECONDS}"
    fi
  fi

  if [ "$CERTBOT_PLUGIN" = "linode" ]; then
    ##
    # Trigger certbot's dns-linode plugin
    #
    # The dns_cloudflare plugin automates the process of completing a dns-01 challenge (DNS01) by creating,
    # and subsequently removing, TXT records using the Cloudflare API.
    # see https://certbot-dns-cloudflare.readthedocs.io/en/stable/
    #
    pluginArgs="--dns-linode --dns-linode-credentials ${credentialsFile}"
    if [ ! -z "${PROPAGATION_SECONDS}" ]; then
      pluginArgs="${pluginArgs} --dns-linode-propagation-seconds ${PROPAGATION_SECONDS}"
    fi
  fi

  local customArgs="${pluginArgs} ${CUSTOM_ARGS}"

  CERTBOT_ARGS=" --preferred-challenges ${PREFERRED_CHALLENGES:-dns-01} ${customArgs}"

  # Activate debug mode
  if [ "$DEBUG" = true ]; then
    CERTBOT_ARGS="${CERTBOT_ARGS} --debug"
  fi

  # Activate staging mode where test certificates (invalid) are requested against
  # letsencrypt's staging server https://acme-staging.api.letsencrypt.org/directory.
  # This is useful for testing purposes without being rate limited by letsencrypt
  if [ "$STAGING" = true ]; then
    logger_info "Running in stagging mode for domain(s): ${DOMAINS}"
    CERTBOT_ARGS=$CERTBOT_ARGS" --staging"
  fi

  logger_info "Using Certbot Args: ${CERTBOT_ARGS}"

  NOW=$(date +"%D %T")
  logger_info "Checking certificates for domains(s) $DOMAINS"

  ##
  # Extract certificate domains and run main routine on each
  # $DOMAINS is expected to be space separated list of domains such as in "foo bar baz"
  # each domains subset can be composed of several domains in case of multi-host domains,
  # they are expected to be comma separated, such as in "foo bar,bat baz"
  #
  for d in $DOMAINS; do
    CERT_DOMAIN=$d
    processCertificates
  done
}

_main "$@"
