# OCI Function: Let's Encrypt renew → OCI Certificates.
# Follows Oracle fnproject layout: pip --target /python, ENTRYPOINT /python/bin/fdk
# Build: linux/amd64
FROM fnproject/python:3.11-dev AS build-stage
WORKDIR /function

COPY requirements.txt vendor/dns_oci.py ./
RUN pip3 install --target /python/ --no-cache-dir -r requirements.txt \
  && mkdir -p /python/certbot_dns_oci /python/certbot_dns_oci-0.0.0.dist-info \
  && cp dns_oci.py /python/certbot_dns_oci/dns_oci.py \
  && touch /python/certbot_dns_oci/__init__.py \
  && printf '%s\n' '[certbot.plugins]' 'dns-oci = certbot_dns_oci.dns_oci:Authenticator' \
     > /python/certbot_dns_oci-0.0.0.dist-info/entry_points.txt

COPY func.py oci_rp.py renew.sh deploy-oci-cert.sh ./
RUN chmod +x renew.sh deploy-oci-cert.sh oci_rp.py \
  && chmod -R o+r /python

FROM fnproject/python:3.11
WORKDIR /function

COPY --from=build-stage /python /python
COPY --from=build-stage /function /function

ENV PYTHONPATH=/function:/python
ENV PATH=/python/bin:/usr/local/bin:$PATH
ENV FN_LISTENER=8080

ENTRYPOINT ["/python/bin/fdk", "/function/func.py", "handler"]
