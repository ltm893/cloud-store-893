import io
import json
import logging
import os
import subprocess

from fdk import response

logger = logging.getLogger(__name__)


def handler(ctx, data: io.BytesIO = None):
    payload = {}
    if data is not None:
        try:
            raw = data.getvalue()
            if raw:
                payload = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError:
            logger.warning("Ignoring non-JSON invoke payload")

    if payload.get("dry_run") or os.environ.get("DRY_RUN") == "1":
        os.environ["DRY_RUN"] = "1"
    if payload.get("force_renew"):
        os.environ["FORCE_RENEW"] = "1"
    if payload.get("smoke_test"):
        os.environ["SMOKE_TEST"] = "1"

    logger.info(
        "cert-renew start hostname=%s dry_run=%s force_renew=%s smoke_test=%s",
        os.environ.get("CERT_HOSTNAME"),
        os.environ.get("DRY_RUN", "0"),
        os.environ.get("FORCE_RENEW", "0"),
        os.environ.get("SMOKE_TEST", "0"),
    )

    if os.environ.get("SMOKE_TEST") == "1":
        proc = subprocess.run(
            ["/function/renew.sh", "--smoke-test"],
            capture_output=True,
            text=True,
            check=False,
        )
    else:
        proc = subprocess.run(
            ["/function/renew.sh"],
            capture_output=True,
            text=True,
            check=False,
        )

    body = {
        "ok": proc.returncode == 0,
        "returncode": proc.returncode,
        "stdout": proc.stdout[-8000:] if proc.stdout else "",
        "stderr": proc.stderr[-8000:] if proc.stderr else "",
    }

    if proc.returncode != 0:
        logger.error("renew.sh failed: %s", proc.stderr)
        return response.Response(
            ctx,
            response_data=json.dumps(body),
            headers={"Content-Type": "application/json"},
            status_code=500,
        )

    logger.info("cert-renew success")
    return response.Response(
        ctx,
        response_data=json.dumps(body),
        headers={"Content-Type": "application/json"},
    )
