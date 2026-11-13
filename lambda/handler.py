"""
Clinical notes processor.

Triggered when a note lands in S3 at notes/<patient_id>/<note_id>.txt

1. Reads the note from S3 (through the S3 gateway endpoint)
2. Finds personal details with Comprehend Medical DetectPHI and blanks them out
3. Extracts conditions, medications, tests, etc. with DetectEntitiesV2
4. Saves the de-identified results to DynamoDB
5. Sends an SNS alert if a watched condition or medication is found

Raw note text is never written to the logs.
"""

import json
import logging
import os
import urllib.parse
from datetime import datetime, timezone
from decimal import Decimal

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")
cm = boto3.client("comprehendmedical")
dynamodb = boto3.resource("dynamodb")
sns = boto3.client("sns")

TABLE = dynamodb.Table(os.environ["TABLE_NAME"])
TOPIC_ARN = os.environ["TOPIC_ARN"]
FLAG_CONDITIONS = {c.strip().lower() for c in os.environ.get("FLAG_CONDITIONS", "").split(",") if c.strip()}
FLAG_MEDICATIONS = {m.strip().lower() for m in os.environ.get("FLAG_MEDICATIONS", "").split(",") if m.strip()}
MAX_CHARS = int(os.environ.get("MAX_CHARS", "5000"))  # keeps Comprehend Medical costs predictable


def handler(event, context):
    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
        process_note(bucket, key)
    return {"status": "ok"}


def process_note(bucket, key):
    patient_id, note_id = parse_key(key)
    logger.info("Processing note_id=%s patient_id=%s", note_id, patient_id)

    body = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
    text = body.decode("utf-8", errors="replace").strip()

    if not text:
        logger.warning("note_id=%s is empty, skipping", note_id)
        return
    if len(text) > MAX_CHARS:
        # Fail loudly rather than run up a bill. Goes to the dead-letter queue.
        raise ValueError(f"note_id={note_id} has {len(text)} chars, limit is {MAX_CHARS}")

    # Step 1: find and remove personal details
    phi = cm.detect_phi(Text=text)["Entities"]
    redacted = redact(text, phi)
    phi_counts = {}
    for e in phi:
        phi_counts[e["Type"]] = phi_counts.get(e["Type"], 0) + 1

    # Step 2: extract clinical information from the de-identified text
    entities = cm.detect_entities_v2(Text=redacted)["Entities"]
    clean_entities = [simplify(e) for e in entities if e["Category"] != "PROTECTED_HEALTH_INFORMATION"]

    # Step 3: decide whether to flag
    reasons = find_flags(clean_entities)

    # Step 4: save. DynamoDB needs Decimal instead of float.
    item = {
        "patient_id": patient_id,
        "note_id": note_id,
        "s3_key": key,
        "processed_at": datetime.now(timezone.utc).isoformat(),
        "redacted_text": redacted,
        "phi_removed": phi_counts,
        "entities": clean_entities,
        "flagged": bool(reasons),
        "flag_reasons": reasons,
    }
    TABLE.put_item(Item=json.loads(json.dumps(item), parse_float=Decimal))
    logger.info(
        "Saved note_id=%s entities=%d phi_removed=%d flagged=%s",
        note_id, len(clean_entities), len(phi), bool(reasons),
    )

    # Step 5: alert. No patient details in the email, just the IDs and reasons.
    if reasons:
        sns.publish(
            TopicArn=TOPIC_ARN,
            Subject="Clinical note flagged for review",
            Message=(
                f"Note {note_id} (patient record {patient_id}) was flagged.\n\n"
                f"Reasons: {'; '.join(reasons)}\n\n"
                "Open the results table in DynamoDB to review it."
            ),
        )


def parse_key(key):
    """notes/<patient_id>/<note_id>.txt -> (patient_id, note_id)"""
    parts = key.split("/")
    note_id = parts[-1].rsplit(".", 1)[0]
    patient_id = parts[-2] if len(parts) >= 3 else "unknown"
    return patient_id, note_id


def redact(text, phi_entities):
    """Replace each personal detail with its type, e.g. [NAME], working backwards so offsets stay valid."""
    out = text
    for e in sorted(phi_entities, key=lambda x: x["BeginOffset"], reverse=True):
        out = out[: e["BeginOffset"]] + f"[{e['Type']}]" + out[e["EndOffset"]:]
    return out


def simplify(e):
    return {
        "text": e["Text"],
        "category": e["Category"],
        "type": e["Type"],
        "score": round(e["Score"], 3),
        "traits": [t["Name"] for t in e.get("Traits", [])],
    }


def find_flags(entities):
    reasons = []
    for e in entities:
        name = e["text"].lower()
        # "denies chest pain" is tagged NEGATION. Don't flag things the patient doesn't have.
        if "NEGATION" in e["traits"]:
            continue
        if e["category"] == "MEDICAL_CONDITION" and any(c in name for c in FLAG_CONDITIONS):
            reasons.append(f"condition: {e['text']}")
        if e["category"] == "MEDICATION" and any(m in name for m in FLAG_MEDICATIONS):
            reasons.append(f"medication: {e['text']}")
    return sorted(set(reasons))
