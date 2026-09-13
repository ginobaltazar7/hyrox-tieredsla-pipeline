-- Description: Executes graph queries directly through Snowflake SQL stored procedure connectors to analyze athlete station transitions and relationships.
-- TODO: Refactor hardcoded test values (ATH_001, London) into a dynamic Snowflake stored procedure loop pulling live records from SILVER tables.

-- 1. Query matching specific athlete, location, and season
CALL NEO4J_GRAPH_APP.PUBLIC.EXECUTE_CYPHER(
    'MATCH (a:Athlete {id: $athlete_id})-[:COMPETED_IN {season: $season}]->(r:RaceEvent {location: "London", season: $season}) '
    'RETURN a.name AS AthleteName, r.division AS Division, r.total_time_minutes AS Time, $season AS Season',
    PARSE_JSON('{"athlete_id": "ATH_001", "season": "8"}')
);

-- 2. Creation query incorporating composite grain (athlete_id + season) and updated_at
CALL NEO4J_GRAPH_APP.PUBLIC.EXECUTE_CYPHER(
    'MERGE (a:Athlete {id: $athlete_id}) ' +
    'MERGE (r:RaceEvent {location: $location, season: $season}) ' +
    'MERGE (a)-[:COMPETED_IN {season: $season, updated_at: $updated_at}]->(r) ' +
    'CREATE (a)-[:TRANSITIONED_TO {duration_mins: $transition_time, season: $season, updated_at: $updated_at}]->' +
    '(s:Station {name: $station_name})',
    PARSE_JSON('{"athlete_id": "ATH_001", "season": "8", "location": "London", "transition_time": 3.8, "station_name": "Sled Push", "updated_at": "' || CURRENT_TIMESTAMP() || '"}')
);
