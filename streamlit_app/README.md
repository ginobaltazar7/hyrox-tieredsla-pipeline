# HYROX Streamlit app

A mobile first web page for the analyst questions in the main README:

| Section | Source table | Chart |
| --- | --- | --- |
| Q1 Station time variance (elite and pro, pooled) | `q1_station_variance` (8 rows) | Ranked bar chart |
| Q2 First km deviation vs degradation | `q2_station_degradation` (5,000 rows) | Scatter with division filter |
| Q2 By division | `q2_deviation_correlation` (7 rows) | Table, shown as is |
| Q5 Registration audit | none | Data notes panel |

## Files

- `app.py`: page layout, charts and footnotes. Only works with pandas DataFrames.
- `data.py`: the only file that talks to Snowflake. A Databricks version would mainly replace this file.
- `requirements.txt`: Python dependencies.
- `.streamlit/config.toml`: theme and settings.

## Environment variables

Set these on Render (never in code or the repo):

| Name | Value |
| --- | --- |
| `SNOWFLAKE_ACCOUNT` | account identifier |
| `SNOWFLAKE_USER` | `HYROX_STREAMLIT_APP` |
| `SNOWFLAKE_PRIVATE_KEY` | full contents of `rsa_key.p8`, including the BEGIN and END lines |
| `SNOWFLAKE_ROLE` | `HYROX_APP_READER` |
| `SNOWFLAKE_WAREHOUSE` | `COMPUTE_WH` |
| `SNOWFLAKE_DATABASE` | `SPORTS_ANALYTICS_DB` |
| `SNOWFLAKE_SCHEMA` | `RAW_BRONZE` |

The key is unencrypted (generated with `-nocrypt`), so no passphrase is needed. If the key is pasted with literal `\n` instead of line breaks, the app restores them.

## Render settings

- **Build command:** `pip install -r streamlit_app/requirements.txt`
- **Start command:** `streamlit run streamlit_app/app.py --server.port $PORT --server.address 0.0.0.0`
- **Python version:** 3.11 or 3.12 (set `PYTHON_VERSION` on Render if needed)

## Run locally

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
- **Grants:** dbt table models are recreated on each run, which drops SELECT grants. Keep `grants={'select': ['HYROX_APP_READER']}` on the three models so the app keeps access.
