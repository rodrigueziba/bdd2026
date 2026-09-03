#!/bin/bash
# =========================================================
# BASES DE DATOS DISTRIBUIDAS - UNTDF
# Despliegue completo del clúster Citus
# =========================================================

set -e

paso () {
    echo ""
    echo "========================================================="
    echo " $1"
    echo "========================================================="
    echo ""
}

esperar_nodo () {
    local contenedor=$1
    echo -n "   $contenedor "
    for i in $(seq 1 60); do
        if docker exec "$contenedor" pg_isready -h 127.0.0.1 -U ezequiel -d untdf_db -q 2>/dev/null; then
            echo " listo."
            return 0
        fi
        echo -n "."
        sleep 2
    done
    echo ""
    echo "   ERROR: $contenedor no respondió a tiempo."
    exit 1
}

psql_coord () {
    docker exec -i nodo_coordinador psql -v ON_ERROR_STOP=1 -U ezequiel -d untdf_db "$@"
}


paso "1. LEVANTANDO LA INFRAESTRUCTURA"
docker compose up -d


paso "2. ESPERANDO QUE LOS TRES MOTORES ACEPTEN CONEXIONES"
esperar_nodo nodo_coordinador
esperar_nodo nodo_ushuaia
esperar_nodo nodo_riogrande
sleep 3


paso "3. REGISTRANDO LOS NODOS EN EL CLÚSTER CITUS"
psql_coord -c "SELECT citus_set_coordinator_host('nodo_coordinador', 5432);"
psql_coord -c "SELECT citus_add_node('nodo_ushuaia', 5432);"
psql_coord -c "SELECT citus_add_node('nodo_riogrande', 5432);"


paso "4. CREANDO EL ESQUEMA LÓGICO (DDL)"
psql_coord < 01_schema.sql


paso "5. APLICANDO EL DISEÑO DISTRIBUIDO Y LA ASIGNACIÓN FÍSICA"
psql_coord < 02_distribucion.sql


paso "6. CARGANDO LOS DATOS INICIALES (DML)"
psql_coord < 03_datos.sql


paso "7. WORKERS ACTIVOS"
psql_coord -c "SELECT * FROM citus_get_active_worker_nodes();"


paso "8. TIPO DE DISTRIBUCIÓN DE CADA TABLA"
psql_coord -c "SELECT table_name, citus_table_type, distribution_column, shard_count
               FROM citus_tables ORDER BY citus_table_type, table_name;"


paso "9. UBICACIÓN FÍSICA DE LOS FRAGMENTOS CON DATOS"
psql_coord -c "
SELECT 'titulaciones' AS tabla, nodename AS nodo, result AS filas
  FROM run_command_on_placements('titulaciones', \$c\$ SELECT count(*) FROM %s \$c\$)
 WHERE result <> '0'
UNION ALL
SELECT 'profesores', nodename, result
  FROM run_command_on_placements('profesores', \$c\$ SELECT count(*) FROM %s \$c\$)
 WHERE result <> '0'
UNION ALL
SELECT 'profesores_nomina', nodename, result
  FROM run_command_on_placements('profesores_nomina', \$c\$ SELECT count(*) FROM %s \$c\$)
 WHERE result <> '0'
ORDER BY nodo, tabla;"


paso "DESPLIEGUE FINALIZADO CORRECTAMENTE"
echo " Conexión al coordinador:"
echo "   docker exec -it nodo_coordinador psql -U ezequiel -d untdf_db"
echo ""
echo " Pruebas:"
echo "   docker exec -i nodo_coordinador psql -U ezequiel -d untdf_db < 04_pruebas.sql"
echo "   ./05_pruebas_nodos.sh"
echo ""