"""HTTP API backend for the serverless portfolio stack.

Routes (API Gateway HTTP API, payload format 2.0):

    GET    /api/health        liveness probe, no data access
    GET    /api/items         list the most recent items, newest first
    POST   /api/items         create an item from {"message": "..."}
    GET    /api/items/{id}    fetch a single item
    DELETE /api/items/{id}    delete a single item

Data model
----------
One partition, time-ordered sort keys::

    pk = "ITEM"
    sk = "<zero-padded epoch seconds>~<uuid4>"

A single-partition table is the right call at this scale and would be the wrong
call at any real one; the trade-off is written up in
``docs/adr/0007-single-partition-dynamodb-model.md``. The sort key is what the
API exposes as ``id``, which keeps reads and deletes to one O(1) request each
and avoids a secondary index. ``~`` separates the two halves because it needs no
escaping in a URL path, unlike ``#``.
"""

from __future__ import annotations

import base64
import json
import logging
import os
import re
import time
import uuid
from typing import Any, Final

import boto3
from boto3.dynamodb.conditions import Key
from botocore.config import Config
from botocore.exceptions import ClientError

LOG_LEVEL: Final[str] = os.environ.get("LOG_LEVEL", "INFO").upper()
TABLE_NAME: Final[str] = os.environ["TABLE_NAME"]
SERVICE_NAME: Final[str] = os.environ.get("SERVICE_NAME", "serverless-portfolio")
ITEM_TTL_DAYS: Final[int] = int(os.environ.get("ITEM_TTL_DAYS", "30"))

HTTP_NO_CONTENT: Final[int] = 204
HTTP_SERVER_ERROR: Final[int] = 500

PARTITION_KEY: Final[str] = "ITEM"
MAX_MESSAGE_LENGTH: Final[int] = 280
DEFAULT_PAGE_SIZE: Final[int] = 25
MAX_PAGE_SIZE: Final[int] = 50
SECONDS_PER_DAY: Final[int] = 86_400

ITEM_ID_PATTERN: Final[re.Pattern[str]] = re.compile(
    r"^\d{11}~[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)

logger = logging.getLogger(SERVICE_NAME)
logger.setLevel(LOG_LEVEL)

# Bounded retries and short socket timeouts so a DynamoDB brown-out surfaces as
# a 503 well inside the Lambda timeout instead of burning the full budget.
_dynamodb = boto3.resource(
    "dynamodb",
    config=Config(
        retries={"max_attempts": 3, "mode": "standard"},
        connect_timeout=2,
        read_timeout=3,
    ),
)
_table = _dynamodb.Table(TABLE_NAME)


class ApiError(Exception):
    """An error that maps cleanly onto an HTTP status code."""

    def __init__(self, status: int, message: str) -> None:
        super().__init__(message)
        self.status = status
        self.message = message


def _log(level: int, event: str, **fields: Any) -> None:
    """Emit one JSON line so Logs Insights can query fields without a parser."""
    logger.log(level, json.dumps({"event": event, "service": SERVICE_NAME, **fields}))


def _response(status: int, body: dict[str, Any] | None = None) -> dict[str, Any]:
    response: dict[str, Any] = {
        "statusCode": status,
        "headers": {"content-type": "application/json", "cache-control": "no-store"},
    }
    if status != HTTP_NO_CONTENT and body is not None:
        response["body"] = json.dumps(body, default=str)
    return response


def _parse_body(event: dict[str, Any]) -> dict[str, Any]:
    raw = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode("utf-8")
    try:
        parsed = json.loads(raw)
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise ApiError(400, "Request body is not valid JSON.") from exc
    if not isinstance(parsed, dict):
        raise ApiError(400, "Request body must be a JSON object.")
    return parsed


def _validate_message(body: dict[str, Any]) -> str:
    message = body.get("message")
    if not isinstance(message, str):
        raise ApiError(400, "Field 'message' is required and must be a string.")
    message = message.strip()
    if not message:
        raise ApiError(400, "Field 'message' must not be empty.")
    if len(message) > MAX_MESSAGE_LENGTH:
        raise ApiError(400, f"Field 'message' must be at most {MAX_MESSAGE_LENGTH} characters.")
    return message


def _validate_item_id(item_id: str) -> str:
    if not ITEM_ID_PATTERN.match(item_id):
        raise ApiError(400, "Malformed item id.")
    return item_id


def _public(item: dict[str, Any]) -> dict[str, Any]:
    """Project a stored item onto the shape the API exposes."""
    return {
        "id": item["sk"],
        "message": item["message"],
        "created_at": int(item["created_at"]),
    }


def create_item(event: dict[str, Any]) -> dict[str, Any]:
    message = _validate_message(_parse_body(event))
    now = int(time.time())
    item = {
        "pk": PARTITION_KEY,
        "sk": f"{now:011d}~{uuid.uuid4()}",
        "message": message,
        "created_at": now,
        "expires_at": now + ITEM_TTL_DAYS * SECONDS_PER_DAY,
    }
    _table.put_item(Item=item)
    return _response(201, _public(item))


def list_items(event: dict[str, Any]) -> dict[str, Any]:
    params = event.get("queryStringParameters") or {}
    raw_limit = params.get("limit", str(DEFAULT_PAGE_SIZE))
    try:
        limit = int(raw_limit)
    except (TypeError, ValueError) as exc:
        raise ApiError(400, "Query parameter 'limit' must be an integer.") from exc
    limit = max(1, min(limit, MAX_PAGE_SIZE))

    result = _table.query(
        KeyConditionExpression=Key("pk").eq(PARTITION_KEY),
        ScanIndexForward=False,
        Limit=limit,
    )
    items = [_public(item) for item in result.get("Items", [])]
    return _response(200, {"items": items, "count": len(items)})


def get_item(item_id: str) -> dict[str, Any]:
    result = _table.get_item(Key={"pk": PARTITION_KEY, "sk": _validate_item_id(item_id)})
    item = result.get("Item")
    if item is None:
        raise ApiError(404, "Item not found.")
    return _response(200, _public(item))


def delete_item(item_id: str) -> dict[str, Any]:
    result = _table.delete_item(
        Key={"pk": PARTITION_KEY, "sk": _validate_item_id(item_id)},
        ReturnValues="ALL_OLD",
    )
    if not result.get("Attributes"):
        raise ApiError(404, "Item not found.")
    return _response(HTTP_NO_CONTENT)


def _route(event: dict[str, Any]) -> dict[str, Any]:
    http = event.get("requestContext", {}).get("http", {})
    method = str(http.get("method", "GET")).upper()
    path = str(http.get("path", "/"))

    if path == "/api/health":
        if method == "GET":
            return _response(200, {"status": "ok", "service": SERVICE_NAME})
        raise ApiError(405, f"Method {method} is not allowed on {path}.")

    if path == "/api/items":
        if method == "GET":
            return list_items(event)
        if method == "POST":
            return create_item(event)
        raise ApiError(405, f"Method {method} is not allowed on {path}.")

    if path.startswith("/api/items/"):
        item_id = path.removeprefix("/api/items/")
        if method == "GET":
            return get_item(item_id)
        if method == "DELETE":
            return delete_item(item_id)
        raise ApiError(405, f"Method {method} is not allowed on {path}.")

    raise ApiError(404, f"No route for {method} {path}.")


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """API Gateway HTTP API entry point."""
    request_id = getattr(context, "aws_request_id", "local")
    http = event.get("requestContext", {}).get("http", {})
    method = http.get("method")
    path = http.get("path")
    started = time.perf_counter()

    def elapsed_ms() -> float:
        return round((time.perf_counter() - started) * 1000, 2)

    try:
        response = _route(event)
    except ApiError as exc:
        _log(
            logging.WARNING if exc.status < HTTP_SERVER_ERROR else logging.ERROR,
            "request_rejected",
            level="WARN" if exc.status < HTTP_SERVER_ERROR else "ERROR",
            request_id=request_id,
            method=method,
            path=path,
            status=exc.status,
            reason=exc.message,
            duration_ms=elapsed_ms(),
        )
        return _response(exc.status, {"error": exc.message})
    except ClientError as exc:
        # Never surface an AWS error verbatim: it leaks table names, ARNs and
        # the account ID to the caller.
        _log(
            logging.ERROR,
            "aws_call_failed",
            level="ERROR",
            request_id=request_id,
            method=method,
            path=path,
            error_code=exc.response.get("Error", {}).get("Code", "Unknown"),
            duration_ms=elapsed_ms(),
        )
        return _response(503, {"error": "Downstream service unavailable."})
    except Exception:
        logger.exception("unhandled_error")
        _log(
            logging.ERROR,
            "unhandled_error",
            level="ERROR",
            request_id=request_id,
            method=method,
            path=path,
            duration_ms=elapsed_ms(),
        )
        return _response(500, {"error": "Internal server error."})

    _log(
        logging.INFO,
        "request_completed",
        level="INFO",
        request_id=request_id,
        method=method,
        path=path,
        status=response["statusCode"],
        duration_ms=elapsed_ms(),
    )
    return response
