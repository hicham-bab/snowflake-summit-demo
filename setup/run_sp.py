#!/usr/bin/env python3
"""
Run SP_STORE_KPI_DAILY against Snowflake.
Usage:
    python3 setup/run_sp.py                  # create + call the SP
    python3 setup/run_sp.py --call-only      # call without recreating
    python3 setup/run_sp.py --create-only    # create without calling
"""

import os
import sys
import argparse
from pathlib import Path
from cryptography.hazmat.primitives.serialization import (
    load_pem_private_key, Encoding, PrivateFormat, NoEncryption
)
import snowflake.connector

# ── Connection ────────────────────────────────────────────────────────────────

ACCOUNT   = os.getenv("SNOWFLAKE_ACCOUNT",   "zna84829")
USER      = os.getenv("SNOWFLAKE_USER",       "HICHAM_BABAHMED")
DATABASE  = os.getenv("SNOWFLAKE_DATABASE",   "ATLAS_PLATFORM")
WAREHOUSE = os.getenv("SNOWFLAKE_WAREHOUSE",  "DBT_DEV_WH")
ROLE      = os.getenv("SNOWFLAKE_ROLE",       "TRANSFORMER")
KEY_PATH  = os.getenv("SNOWFLAKE_KEY_PATH",
                      str(Path.home() / ".snowflake/keys/final_private.pem"))

SP_FILE   = Path(__file__).parent / "sp_store_kpi_daily.sql"


def get_private_key():
    with open(KEY_PATH, "rb") as f:
        p_key = load_pem_private_key(f.read(), password=None)
    return p_key.private_bytes(
        encoding=Encoding.DER,
        format=PrivateFormat.PKCS8,
        encryption_algorithm=NoEncryption()
    )


def connect():
    print(f"Connecting → {ACCOUNT} as {USER} (warehouse: {WAREHOUSE})")
    return snowflake.connector.connect(
        account=ACCOUNT,
        user=USER,
        private_key=get_private_key(),
        database=DATABASE,
        warehouse=WAREHOUSE,
        role=ROLE,
    )


# ── Actions ───────────────────────────────────────────────────────────────────

def create_sp(cur):
    print(f"Creating SP from {SP_FILE} ...")
    sql = SP_FILE.read_text()
    # strip the run comment at the bottom — execute only the CREATE statement
    create_sql = sql.split("-- run it:")[0].strip()
    cur.execute(create_sql)
    print("SP created.")


def call_sp(cur):
    print("Calling SP_STORE_KPI_DAILY ...")
    cur.execute("CALL ATLAS_PLATFORM.PUBLIC.SP_STORE_KPI_DAILY()")
    result = cur.fetchone()
    print(f"SP returned: {result[0]}")


def preview_output(cur):
    print("\nTop 5 rows from STORE_KPI_DAILY:")
    cur.execute("""
        SELECT store_name, order_date, comp_orders, net_rev,
               ret_rate_pct, realized_rev, perf_tier
        FROM ATLAS_PLATFORM.PUBLIC.STORE_KPI_DAILY
        ORDER BY order_date DESC, net_rev DESC
        LIMIT 5
    """)
    cols = [d[0] for d in cur.description]
    print("  " + " | ".join(f"{c:>15}" for c in cols))
    print("  " + "-" * (18 * len(cols)))
    for row in cur.fetchall():
        print("  " + " | ".join(f"{str(v):>15}" for v in row))


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--call-only",   action="store_true")
    parser.add_argument("--create-only", action="store_true")
    args = parser.parse_args()

    conn = connect()
    cur  = conn.cursor()

    try:
        if not args.call_only:
            create_sp(cur)
        if not args.create_only:
            call_sp(cur)
            preview_output(cur)
    finally:
        cur.close()
        conn.close()
        print("\nDone.")


if __name__ == "__main__":
    main()
