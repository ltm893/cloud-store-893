"""DNS Authenticator for OCI (vendored + resource principal for OCI Functions)."""
import logging

from certbot import errors
from certbot import interfaces
from certbot.plugins import dns_common

import oci

logger = logging.getLogger(__name__)


class Authenticator(dns_common.DNSAuthenticator):
    """DNS Authenticator for Oracle Cloud Infrastructure DNS service."""

    description = "Obtain certificates using a DNS TXT record (if you are using OCI for DNS)."
    ttl = 60

    def __init__(self, *args, **kwargs):
        super(Authenticator, self).__init__(*args, **kwargs)

    @classmethod
    def add_parser_arguments(cls, add):
        super(Authenticator, cls).add_parser_arguments(
            add, default_propagation_seconds=60
        )
        add('config', help="OCI CLI Configuration file.")
        add('profile', help="OCI configuration profile (in OCI configuration file)")
        add('instance-principal', help="Use OCI resource/instance principal for authentication.")

    def validate_options(self):
        if self.conf('instance-principal') and self.conf('config'):
            raise errors.PluginError(
                "Conflicting arguments: '--dns-oci-instance-principal' and '--dns-oci-config'."
            )

    def more_info(self):
        return (
            "This plugin configures a DNS TXT record to respond to a dns-01 challenge using "
            "the OCI REST API."
        )

    def _setup_credentials(self):
        self.validate_options()
        if self.conf('instance-principal') is None:
            oci_config_profile = self.conf('profile') or 'DEFAULT'
            self.credentials = oci.config.from_file(profile_name=oci_config_profile)

    def _perform(self, domain, validation_name, validation):
        self._get_ocidns_client().add_txt_record(
            domain, validation_name, validation, self.ttl
        )

    def _cleanup(self, domain, validation_name, validation):
        self._get_ocidns_client().del_txt_record(
            domain, validation_name, validation
        )

    def _get_ocidns_client(self):
        if self.conf('instance-principal') is not None:
            return _OCIDNSClient(None)
        return _OCIDNSClient(self.credentials)


class _OCIDNSClient:
    def __init__(self, oci_config=None):
        if oci_config is not None:
            self.dns_client = oci.dns.DnsClient(oci_config)
        else:
            logger.debug("creating OCI DnsClient using resource principal")
            signer = oci.auth.signers.get_resource_principals_signer()
            self.dns_client = oci.dns.DnsClient(config={}, signer=signer)

    def add_txt_record(self, domain, record_name, record_content, record_ttl):
        zone_ocid, zone_name = self._find_managed_zone(domain, record_name)
        if zone_name is None:
            raise errors.PluginError(
                "Domain not known. Ensure the zone is in OCI DNS with correct permissions."
            )
        self.dns_client.patch_domain_records(
            zone_name,
            record_name,
            oci.dns.models.PatchDomainRecordsDetails(
                items=[
                    oci.dns.models.RecordOperation(
                        operation='ADD',
                        domain=record_name,
                        ttl=record_ttl,
                        rtype='TXT',
                        rdata=record_content,
                    )
                ]
            ),
        )

    def del_txt_record(self, domain, record_name, record_content):
        zone_ocid, zone_name = self._find_managed_zone(domain, record_name)
        if zone_name is None:
            raise errors.PluginError("Domain not known")
        self.dns_client.patch_domain_records(
            zone_name,
            record_name,
            oci.dns.models.PatchDomainRecordsDetails(
                items=[
                    oci.dns.models.RecordOperation(
                        operation='REMOVE',
                        domain=record_name,
                        rtype='TXT',
                        rdata=record_content,
                    )
                ]
            ),
        )

    def _find_managed_zone(self, domain, record_name):
        zone_dns_name_guesses = [record_name] + dns_common.base_domain_name_guesses(domain)
        for zone_name in zone_dns_name_guesses:
            try:
                response = self.dns_client.get_zone(zone_name)
                if response.status == 200:
                    return response.data.id, zone_name
            except oci.exceptions.ServiceError:
                pass
        return None, None
