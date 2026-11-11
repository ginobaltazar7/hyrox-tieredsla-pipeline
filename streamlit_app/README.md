# HYROX Streamlit app

A mobile first web page for the analyst questions in the main README:

| Section | Source table | Chart |
| --- | --- | --- |
| Q1 Station time variance (elite and pro, pooled) | `q1_station_variance` (8 rows) | Ranked bar chart |
| Q2 First km deviation vs degradation | `q2_station_degradation` (5,000 rows) | Scatter with division filter |
| Q2 By division | `q2_deviation_correlation` (7 rows) | Table, shown as is |
| Q5 Registration audit | none | Data notes panel |

The live deploy read Snowflake on a trial that ended around 10 Nov 2026. To run this app now: either a fresh Snowflake trial or paid account (follow RUNBOOK.md — the access setup is in `sql/streamlit_access.sql`), or the Databricks version, which replaces `data.py` only (see the hyrox-databricks-port repo).

## Files

- `app.py`: page layout, charts and footnotes. Only works with pandas DataFrames.
- `data.py`: the only file that talks to Snowflake. A Databricks version of this file is built (hyrox-databricks-port repo, `streamlit_app/data.py`); `app.py` is unchanged between the two.
- `requirements.txt`: Python dependencies.
- `.streamlit/config.toml`: theme and settings.

## Environment variables

Set these on Render (never in code or the repo):

| Name | Value |
| --- | --- |
| `SNOWFLAKE_ACCOUNT` | account identifier, `<org>-<account>` format, e.g. `PIIZXJY-VRB18725` for this repo's live deploy — not the locator `CURRENT_ACCOUNT()` returns |
| `SNOWFLAKE_USER` | `HYROX_STREAMLIT_APP` |
| `SNOWFLAKE_PRIVATE_KEY` | full contents of `rsa_key.p8`, including the BEGIN and END lines |
| `SNOWFLAKE_ROLE` | `HYROX_APP_READER` |
| `SNOWFLAKE_WAREHOUSE` | `COMPUTE_WH` |
| `SNOWFLAKE_DATABASE` | `SPORTS_ANALYTICS_DB` |
| `SNOWFLAKE_SCHEMA` | `RAW_BRONZE` |

The schema is `RAW_BRONZE` because the gold-tier models materialise there — see the main README, Schema placement — not because the app reads raw data.

The key is unencrypted (generated with `-nocrypt`), so no passphrase is needed. If the key is pasted with literal `\n` instead of line breaks, the app restores them.

Make the key pair on your own machine in a folder that survives a reboot — never in a temp folder — and never commit the private key. If you make a new key pair later, update the user too: `ALTER USER HYROX_STREAMLIT_APP SET RSA_PUBLIC_KEY = '<the long middle line of the public key>'` — making a new pair alone isn't enough, Snowflake still holds the old public key until you do that.

## Render settings

- **Build command:** `pip install -r streamlit_app/requirements.txt`
- **Start command:** `streamlit run streamlit_app/app.py --server.port $PORT --server.address 0.0.0.0`
- **Python version:** 3.11 or 3.12 (set `PYTHON_VERSION` on Render if needed)

## Run locally

Use Python 3.11 or 3.12 locally too (a venv). On a Mac with Python 3.14, Altair 5 fails on import — don't edit the `altair>=5,<6` pin in `requirements.txt` to work around it.

Against Snowflake (export the 7 variables first):

```
pip install -r streamlit_app/requirements.txt
streamlit run streamlit_app/app.py
```

Local preview without Snowflake (development only, not used on Render): put
`q1_station_variance.csv` and `q2_station_degradation.csv` in a folder outside the repo, then

```
HYROX_LOCAL_DATA_DIR=/path/to/folder streamlit run streamlit_app/app.py
```

In preview mode the correlation table is rebuilt from the CSV with the same logic as the dbt model.

## Behaviour worth knowing

- **Caching:** each table is queried at most once an hour, so page views don't wake the warehouse.
- **Q2 chart range:** the scatter's default view is first km deviation from -12 to +4 minutes (`Q2_X_DOMAIN` in `app.py`). All rows stay in the data and in the correlation table. The footnote counts the points outside the range for the selected division, so it reads "4 points fall outside the chart range." on the pooled view.
- **Division filter:** each division is shown on its own by default (Open first). The pooled view is labelled as pooled.
- **Small groups:** Elite and Elite Doubles (n = 29) show a warning.
- **Errors:** if Snowflake is unreachable, visitors see a short message and the technical detail sits in a collapsed box.
- **Grants:** the account-side half of this lives in `sql/streamlit_access.sql` — it creates the role, the service user, and the grants. The dbt side is the keep-alive half: dbt table models are recreated on each run, which drops SELECT grants. Keep `grants={'select': ['HYROX_APP_READER']}` on the three models so the app keeps access.

<sub>Parts of this project, including documentation and analysis, were developed with assistance from Naru, an AI assistant.</sub>