#!/usr/bin/env python3
"""OCI operations via resource principal (replaces oci-cli in Functions)."""

from __future__ import annotations

import argparse
import sys

import oci


def _signer():
    return oci.auth.signers.get_resource_principals_signer()


def _object_storage():
    signer = _signer()
    client = oci.object_storage.ObjectStorageClient(config={}, signer=signer)
    namespace = client.get_namespace().data
    return client, namespace


def os_head(bucket: str, name: str) -> int:
    client, namespace = _object_storage()
    try:
        client.head_object(namespace, bucket, name)
    except oci.exceptions.ServiceError as exc:
        if exc.status == 404:
            return 1
        raise
    return 0


def os_get(bucket: str, name: str, path: str) -> None:
    client, namespace = _object_storage()
    response = client.get_object(namespace, bucket, name)
    with open(path, "wb") as handle:
        for chunk in response.data.raw.stream(1024 * 1024, decode_content=False):
            handle.write(chunk)


def os_put(bucket: str, name: str, path: str) -> None:
    client, namespace = _object_storage()
    with open(path, "rb") as handle:
        client.put_object(namespace, bucket, name, handle)


def cert_import(certificate_id: str, cert_path: str, key_path: str, chain_path: str) -> None:
    signer = _signer()
    client = oci.certificates_management.CertificatesManagementClient(config={}, signer=signer)
    with open(cert_path, encoding="utf-8") as handle:
        certificate_pem = handle.read()
    with open(key_path, encoding="utf-8") as handle:
        private_key_pem = handle.read()
    with open(chain_path, encoding="utf-8") as handle:
        cert_chain_pem = handle.read()

    details = oci.certificates_management.models.UpdateCertificateByImportingConfigDetails(
        certificate_pem=certificate_pem,
        private_key_pem=private_key_pem,
        cert_chain_pem=cert_chain_pem,
    )
    client.update_certificate_by_importing_config_details(certificate_id, details)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    head = sub.add_parser("os-head", help="exit 0 if object exists")
    head.add_argument("--bucket", required=True)
    head.add_argument("--name", required=True)

    get = sub.add_parser("os-get", help="download object to file")
    get.add_argument("--bucket", required=True)
    get.add_argument("--name", required=True)
    get.add_argument("--file", required=True)

    put = sub.add_parser("os-put", help="upload file to object")
    put.add_argument("--bucket", required=True)
    put.add_argument("--name", required=True)
    put.add_argument("--file", required=True)

    cert = sub.add_parser("cert-import", help="import PEMs into OCI Certificates")
    cert.add_argument("--certificate-id", required=True)
    cert.add_argument("--cert", required=True)
    cert.add_argument("--key", required=True)
    cert.add_argument("--chain", required=True)

    args = parser.parse_args(argv)

    if args.command == "os-head":
        return os_head(args.bucket, args.name)
    if args.command == "os-get":
        os_get(args.bucket, args.name, args.file)
        return 0
    if args.command == "os-put":
        os_put(args.bucket, args.name, args.file)
        return 0
    if args.command == "cert-import":
        cert_import(args.certificate_id, args.cert, args.key, args.chain)
        return 0

    parser.error(f"unknown command: {args.command}")
    return 2


if __name__ == "__main__":
    sys.exit(main())
