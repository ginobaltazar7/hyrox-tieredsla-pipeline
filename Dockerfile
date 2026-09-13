FROM python:3.11-slim

WORKDIR /app

# Install system build essentials
RUN apt-get update && apt-get install -y --no-install-recommends build-essential && rm -rf /var/lib/apt/lists/*

# Install all project dependencies (dbt-snowflake, snowpark, pyrox,etc.)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Explicitly copy scripts and project source code into container
COPY scripts/ ./scripts/
COPY utils/ ./utils/
COPY dbt_project/ ./dbt_project/

# Default fallback command if the container runs without arguments
CMD ["dbt", "run"]