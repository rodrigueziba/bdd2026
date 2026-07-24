#!/bin/bash

# Este script levanta los servidores y ejecuta los archivos SQL automáticamente.

echo "====================================================="
echo "1. Levantando la infraestructura con Docker..."
echo "====================================================="
docker compose up -d

echo " "
echo "Esperando 20 segundos para que PostgreSQL inicie correctamente..."
sleep 20
echo " "

echo "====================================================="
echo "2. Iniciando la configuración de la BD Distribuida..."
echo "====================================================="

# Unir los nodos
echo "-> Configurando la red de Citus..."
docker exec -i nodo_coordinador psql -U ezequiel -d untdf_db -c "SELECT citus_set_coordinator_host('nodo_coordinador', 5432);"
docker exec -i nodo_coordinador psql -U ezequiel -d untdf_db -c "SELECT citus_add_node('nodo_ushuaia', 5432);"
docker exec -i nodo_coordinador psql -U ezequiel -d untdf_db -c "SELECT citus_add_node('nodo_riogrande', 5432);"

# Ejecutar el esquema lógico
echo "-> Creando el Esquema Lógico (01_schema.sql)..."
docker exec -i nodo_coordinador psql -U ezequiel -d untdf_db < 01_schema.sql

# Ejecutar la distribución
echo "-> Aplicando Distribución y Replicación (02_distribucion.sql)..."
docker exec -i nodo_coordinador psql -U ezequiel -d untdf_db < 02_distribucion.sql

# Cargar los datos
echo "-> Cargando datos de prueba (03_datos.sql)..."
docker exec -i nodo_coordinador psql -U ezequiel -d untdf_db < 03_datos.sql

echo " "
echo "====================================================="
echo "¡Proceso terminado exitosamente!"
echo "Verificando los nodos activos:"
docker exec -i nodo_coordinador psql -U ezequiel -d untdf_db -c "SELECT * FROM citus_get_active_worker_nodes();"
echo "====================================================="