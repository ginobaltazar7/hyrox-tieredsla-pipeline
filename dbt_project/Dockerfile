FROM python:3.11-slim

WORKDIR /app

# Install dbt and the Snowflake adapter
RUN pip install --no-cache-dir dbt-snowflake

# Copy your dbt project files into the container
COPY . /app/

# Default entrypoint to run dbt models when the container starts
ENTRYPOINT ["dbt", "run"]