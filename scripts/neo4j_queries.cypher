// Neo4j proof queries — Hyrox schema lineage, v1.
// Default: verified only (gold / signal tier). Remove the status filter
// for full lineage all the way to bronze (tagged unverified).

// 1. Upstream, verified only: what feeds q1_station_variance?
MATCH (m:Model {name: 'q1_station_variance', status: 'verified'})
      -[:DERIVED_FROM*1..3]->(up)
WHERE up.status = 'verified'
RETURN m, up;

// 1b. Upstream, full lineage to bronze:
MATCH (m:Model {name: 'q1_station_variance'})-[:DERIVED_FROM*1..3]->(up)
RETURN m, up;

// 2. Downstream impact, verified only: what breaks if total_time_minutes changes?
MATCH (c:Column {name: 'total_time_minutes', status: 'verified'})<-[:CONTAINS]-(m)
MATCH (down)-[:DERIVED_FROM*0..3]->(m)
RETURN c, m, down;

// 3. Metric dependency, verified only: which metrics depend on division?
MATCH (metric:Metric {status: 'verified'})-[:DEFINED_ON]->(m:Model)-[:CONTAINS]->(c:Column {name: 'division', status: 'verified'})
RETURN metric, m;
