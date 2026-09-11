--Description: Executes graph queries directly through Snowflake SQL stored procedure connectors to analyze athlete station transitions and relationships.
SQL
CALL NEO4J_GRAPH_APP.PUBLIC.EXECUTE_CYPHER(
    'MATCH (a:Athlete)-[:COMPETED_IN]->(r:RaceEvent {location: "London"}) '
    'RETURN a.name AS AthleteName, r.division AS Division, a.total_time_minutes AS Time'
);

CALL NEO4J_GRAPH_APP.PUBLIC.EXECUTE_CYPHER(
    'CREATE (a:Athlete {id: $athlete_id})-' +
    '[:TRANSITIONED_TO {duration_mins: $transition_time}]->' +
    '(s:Station {name: $station_name})',
    PARSE_JSON('{"athlete_id": "ATH_001", "transition_time": 3.8, "station_name": "Sled Push"}')
);
