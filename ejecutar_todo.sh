#!/bin/bash

set -e

echo "====================================================="
echo " BASES DE DATOS DISTRIBUIDAS - UNTDF"
echo "====================================================="

echo ""
echo "1. Levantando infraestructura Docker..."
echo ""

docker compose up -d

echo ""
echo "2. Esperando disponibilidad de PostgreSQL..."
echo ""

sleep 20

echo ""
echo "3. Configurando Citus..."
echo ""

docker exec -i nodo_coordinador \
    psql -U ezequiel -d untdf_db \
    -c "SELECT citus_set_coordinator_host('nodo_coordinador', 5432);"

docker exec -i nodo_coordinador \
    psql -U ezequiel -d untdf_db \
    -c "SELECT citus_add_node('nodo_ushuaia', 5432);"

docker exec -i nodo_coordinador \
    psql -U ezequiel -d untdf_db \
    -c "SELECT citus_add_node('nodo_riogrande', 5432);"


echo ""
echo "4. Creando esquema lógico..."
echo ""

docker exec -i nodo_coordinador \
    psql -v ON_ERROR_STOP=1 \
    -U ezequiel \
    -d untdf_db \
    < 01_schema.sql


echo ""
echo "5. Aplicando distribución Citus..."
echo ""

docker exec -i nodo_coordinador \
    psql -v ON_ERROR_STOP=1 \
    -U ezequiel \
    -d untdf_db \
    < 02_distribucion.sql


echo ""
echo "6. Cargando datos iniciales..."
echo ""

docker exec -i nodo_coordinador \
    psql -v ON_ERROR_STOP=1 \
    -U ezequiel \
    -d untdf_db \
    < 03_datos.sql


echo ""
echo "====================================================="
echo " CONFIGURACIÓN FINALIZADA CORRECTAMENTE"
echo "====================================================="

echo ""
echo "7. Workers activos:"
echo ""

docker exec -i nodo_coordinador \
    psql -U ezequiel \
    -d untdf_db \
    -c "SELECT * FROM citus_get_active_worker_nodes();"


echo ""
echo "8. Distribución de tablas:"
echo ""

docker exec -i nodo_coordinador \
    psql -U ezequiel \
    -d untdf_db \
    -c "SELECT table_name, citus_table_type, distribution_column, shard_count FROM citus_tables ORDER BY table_name;"


echo ""
echo "====================================================="
echo " FIN"
echo "====================================================="