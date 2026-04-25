"""ShopCloud invoice generator.

Receives OrderCompleted events from SQS,
renders a PDF invoice, writes it to S3, and emails a link via SES.
"""
from __future__ import annotations

import io
import json
import logging
import os
from datetime import datetime, timezone
from decimal import Decimal

import boto3
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.platypus import (
    SimpleDocTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)
from reportlab.lib import colors


LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO").upper()
logging.basicConfig(level=LOG_LEVEL)
log = logging.getLogger("invoice")

INVOICE_BUCKET = os.environ["INVOICE_BUCKET"]
SES_FROM_ADDRESS = os.environ["SES_FROM_ADDRESS"]

s3 = boto3.client("s3")
ses = boto3.client("ses")


def _render_pdf(order: dict) -> bytes:
    """Render an order dict into a PDF."""
    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=letter)
    styles = getSampleStyleSheet()
    story: list = []

    story.append(Paragraph("ShopCloud Invoice", styles["Title"]))
    story.append(Spacer(1, 12))
    story.append(
        Paragraph(
            f"Order <b>{order['order_id']}</b> &nbsp;&nbsp;"
            f"Date: {datetime.now(timezone.utc).isoformat(timespec='seconds')}",
            styles["Normal"],
        )
    )
    story.append(
        Paragraph(f"Billed to: {order['customer_email']}", styles["Normal"])
    )
    story.append(Spacer(1, 18))

    rows = [["Item", "Qty", "Unit", "Subtotal"]]
    for item in order.get("items", []):
        qty = Decimal(str(item.get("qty", 1)))
        unit = Decimal(str(item.get("price", 0)))
        rows.append(
            [
                item.get("name", "item"),
                str(qty),
                f"{unit:.2f}",
                f"{qty * unit:.2f}",
            ]
        )
    rows.append(["", "", "Total", f"{order['total']} {order.get('currency', 'USD')}"])

    table = Table(rows, hAlign="LEFT")
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.lightgrey),
                ("GRID", (0, 0), (-1, -1), 0.3, colors.grey),
                ("ALIGN", (1, 1), (-1, -1), "RIGHT"),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
            ]
        )
    )
    story.append(table)
    doc.build(story)
    return buf.getvalue()


def _put_invoice(order_id: str, pdf_bytes: bytes) -> str:
    key = f"invoices/{datetime.now(timezone.utc):%Y/%m/%d}/{order_id}.pdf"
    s3.put_object(
        Bucket=INVOICE_BUCKET,
        Key=key,
        Body=pdf_bytes,
        ContentType="application/pdf",
        ServerSideEncryption="AES256",
    )
    return key


def _send_email(to_email: str, order_id: str, s3_key: str) -> None:
    ses.send_email(
        Source=SES_FROM_ADDRESS,
        Destination={"ToAddresses": [to_email]},
        Message={
            "Subject": {
                "Data": f"Your ShopCloud invoice for order {order_id}"
            },
            "Body": {
                "Html": {
                    "Data": (
                        f"<p>Thanks for your order <b>{order_id}</b>.</p>"
                        f"<p>Your invoice is stored at "
                        f"<code>s3://{INVOICE_BUCKET}/{s3_key}</code>.</p>"
                    )
                },
                "Text": {
                    "Data": (
                        f"Thanks for your order {order_id}. "
                        f"Invoice: s3://{INVOICE_BUCKET}/{s3_key}"
                    )
                },
            },
        },
    )


def _parse_event(record: dict) -> dict:
    body = json.loads(record["body"])
    return body.get("detail", body)


def lambda_handler(event, context):
    """SQS event handler. Uses batch item failures so a single bad
    record doesn't cause the whole batch to be redelivered."""
    log.info("received %d records", len(event.get("Records", [])))
    failures: list[dict] = []

    for record in event.get("Records", []):
        message_id = record["messageId"]
        try:
            order = _parse_event(record)
            pdf = _render_pdf(order)
            key = _put_invoice(order["order_id"], pdf)
            _send_email(order["customer_email"], order["order_id"], key)
            log.info("processed order=%s key=%s", order["order_id"], key)
        except Exception:
            log.exception("failed to process record %s", message_id)
            failures.append({"itemIdentifier": message_id})

    return {"batchItemFailures": failures}
