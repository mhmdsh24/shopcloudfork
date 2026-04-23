"""Invoice generator — container variant of the Lambda handler.

This image is only needed if you want to run the invoice pipeline
outside Lambda (e.g. on ECS during DR when SQS is still in the
primary region and you've wired a regional SQS as a backup). For
normal operation, the Lambda built by terraform/modules/sqs-lambda
is used.
"""
from __future__ import annotations

from fastapi import FastAPI

app = FastAPI(title="shopcloud-invoice-generator")


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "ok", "service": "invoice-generator"}


@app.get("/ready")
def ready() -> dict:
    return {"ready": True, "service": "invoice-generator"}
