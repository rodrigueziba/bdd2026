#!/bin/bash
# =========================================================
# BASES DE DATOS DISTRIBUIDAS - UNTDF
# 05 - PRUEBAS EJECUTADAS DENTRO DE CADA NODO
# =========================================================
# Estas pruebas no pasan por el coordinador: se conectan
# directamente a cada servidor de campus, tal como pide la
# consigna.
#
# NOTA TÉCNICA IMPORTANTE
# -----------------------
# A partir de Citus 11, los fragmentos (shards) quedan
# OCULTOS en el catálogo pg_class para toda aplicación
# cliente. Es una decisión de diseño de Citus para que
# herramientas como pgAdmin no muestren decenas de tablas
# internas junto a las tablas del usuario. El comportamiento
# se controla con el parámetro
# citus.show_shards_for_app_name_prefixes, cuyo valor por
# defecto oculta los fragmentos a todos los clientes.
#
# Consecuencia: una consulta a pg_class desde psql NO
# devuelve los fragmentos, aunque existan físicamente.
#
# Este guión resuelve el problema de dos maneras:
#   1) Desactiva el ocultamiento al inicio de cada sesión.
#   2) Obtiene los nombres de los fragmentos desde los
#      catálogos de Citus (pg_dist_shard, pg_dist_placement,
#      pg_dist_node), que sí están disponibles en cada nodo
#      por la sincronización de metadatos.
#
# El conteo de filas se hace igual sobre la tabla física:
# el nombre viene del catálogo, pero el número lo devuelve
# la tabla real alojada en ese disco.
# =========================================================

set -u

titulo () {
    echo ""
    echo "========================================================="
    echo " $1"
    echo "========================================================="
}

# ---------------------------------------------------------
# Desactiva el ocultamiento de fragmentos para esta sesión.
# Se envuelve en bloques con manejo de excepciones para que
# el guión funcione aunque alguno de los dos parámetros no
# exista en la versión de Citus instalada.
# ---------------------------------------------------------
PREAMBULO="
DO \$pre\$
BEGIN
    BEGIN
        PERFORM set_config('citus.override_table_visibility', 'false', false);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    BEGIN
        PERFORM set_config('citus.show_shards_for_app_name_prefixes', '*', false);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
END
\$pre\$;
"

# ---------------------------------------------------------
# Devuelve los fragmentos alojados en el nodo indicado, con
# la cantidad REAL de filas de cada uno.
#   $1 = nombre del nodo
#   $2 = lista SQL de tablas a considerar
# ---------------------------------------------------------
sql_fragmentos () {
cat <<SQL
SELECT *
FROM (
    SELECT (s.logicalrelid::regclass::text || '_' || s.shardid) AS fragmento_fisico,
           (xpath('/row/c/text()',
                  query_to_xml('SELECT count(*) AS c FROM public.' ||
                               quote_ident(s.logicalrelid::regclass::text || '_' || s.shardid),
                               false, true, '')
           ))[1]::text::int AS filas_reales
    FROM pg_dist_shard s
    JOIN pg_dist_placement p ON p.shardid = s.shardid
    JOIN pg_dist_node      n ON n.groupid = p.groupid
    WHERE n.nodename = '$1'
      AND s.logicalrelid::regclass::text IN ($2)
) t
WHERE filas_reales > 0
ORDER BY 1;
SQL
}

TABLAS_DIST="'titulaciones','cursos','grupos','asignaturas','profesores','imparte','profesores_nomina'"
TABLAS_REF="'pluses_hijo','clasificaciones'"


titulo "PRUEBA A - QUÉ HAY FÍSICAMENTE EN nodo_ushuaia"
echo " Se listan los fragmentos alojados en el servidor de"
echo " Ushuaia y se cuentan sus filas reales."
echo ""
echo " Esperado:"
echo "   titulaciones 2 | cursos 3 | grupos 4 | asignaturas 4"
echo "   profesores 3   | imparte 4 | profesores_nomina 5"
echo ""
echo " Los fragmentos vacíos se omiten de la salida."
echo ""
docker exec -i nodo_ushuaia psql -U ezequiel -d untdf_db \
    -c "$PREAMBULO $(sql_fragmentos nodo_ushuaia "$TABLAS_DIST")"


titulo "PRUEBA B - QUÉ HAY FÍSICAMENTE EN nodo_riogrande"
echo " Esperado:"
echo "   titulaciones 1 | cursos 1 | grupos 1 | asignaturas 3"
echo "   profesores 2   | imparte 2"
echo ""
echo " profesores_nomina NO debe aparecer: es el fragmento"
echo " vertical alojado en la sede central de Ushuaia."
echo ""
docker exec -i nodo_riogrande psql -U ezequiel -d untdf_db \
    -c "$PREAMBULO $(sql_fragmentos nodo_riogrande "$TABLAS_DIST")"


titulo "PRUEBA C - CONTENIDO REAL DEL FRAGMENTO DE CADA SEDE"
echo " Se lee directamente la tabla física de profesores"
echo " alojada en cada nodo. No es una tabla distribuida:"
echo " es una tabla PostgreSQL ordinaria, y lo que devuelve"
echo " es literalmente lo que hay en ese disco."
echo ""
echo " Esperado: Ushuaia muestra 3 docentes de Ushuaia y"
echo " Río Grande muestra 2 de Río Grande. Ningún cruce."
echo ""

leer_fragmento_profesores () {
    local NODO=$1
    echo "--- $NODO ---"
    docker exec -i $NODO psql -U ezequiel -d untdf_db -c "$PREAMBULO
DO \$blq\$
DECLARE
    v_frag TEXT;
    r RECORD;
BEGIN
    SELECT (s.logicalrelid::regclass::text || '_' || s.shardid)
      INTO v_frag
    FROM pg_dist_shard s
    JOIN pg_dist_placement p ON p.shardid = s.shardid
    JOIN pg_dist_node      n ON n.groupid = p.groupid
    WHERE n.nodename = '$NODO'
      AND s.logicalrelid::regclass::text = 'profesores'
      AND (xpath('/row/c/text()',
                 query_to_xml('SELECT count(*) AS c FROM public.' ||
                              quote_ident(s.logicalrelid::regclass::text || '_' || s.shardid),
                              false, true, '')
          ))[1]::text::int > 0
    LIMIT 1;

    IF v_frag IS NULL THEN
        RAISE NOTICE 'Este nodo no aloja ningun fragmento de profesores con datos.';
        RETURN;
    END IF;

    RAISE NOTICE 'Tabla fisica leida: public.%', v_frag;
    FOR r IN EXECUTE
        'SELECT id_profesor, nombre, campus FROM public.' || quote_ident(v_frag) || ' ORDER BY id_profesor'
    LOOP
        RAISE NOTICE '   % | % | %', r.id_profesor, r.nombre, r.campus;
    END LOOP;
END
\$blq\$;"
    echo ""
}

leer_fragmento_profesores nodo_ushuaia
leer_fragmento_profesores nodo_riogrande


titulo "PRUEBA D - CATÁLOGOS REPLICADOS PRESENTES EN CADA NODO"
echo " Las Reference Tables mantienen una copia íntegra en"
echo " todos los nodos. Cada sede resuelve estas consultas de"
echo " forma local, sin pedirle nada al otro servidor."
echo ""
echo " Esperado: 3 filas de pluses_hijo y 3 de clasificaciones"
echo " en cada uno de los dos nodos."
echo ""
for NODO in nodo_ushuaia nodo_riogrande; do
    echo "--- $NODO ---"
    docker exec -i $NODO psql -U ezequiel -d untdf_db \
        -c "$PREAMBULO $(sql_fragmentos $NODO "$TABLAS_REF")"
done


titulo "PRUEBA E - ACCESO A LOS DATOS DE USHUAIA DESDE RÍO GRANDE"
echo " Requerimiento de la consigna. Nos conectamos al servidor"
echo " de Río Grande y consultamos datos que están físicamente"
echo " en Ushuaia. Citus resuelve el acceso remoto de forma"
echo " transparente."
echo ""
echo " Esperado: los 3 docentes de Ushuaia."
echo ""
docker exec -i nodo_riogrande psql -U ezequiel -d untdf_db -c "
SELECT id_profesor, nombre, campus FROM profesores WHERE campus = 'Ushuaia' ORDER BY id_profesor;"


titulo "PRUEBA F - ACCESO A LOS DATOS DE RÍO GRANDE DESDE USHUAIA"
echo " El requerimiento simétrico."
echo ""
echo " Esperado: los 2 docentes de Río Grande."
echo ""
docker exec -i nodo_ushuaia psql -U ezequiel -d untdf_db -c "
SELECT id_profesor, nombre, campus FROM profesores WHERE campus = 'Rio Grande' ORDER BY id_profesor;"


titulo "PRUEBA G - ESCRITURA DESDE UNA SEDE SOBRE LA OTRA"
echo " Se da de alta, desde el servidor de Río Grande, una"
echo " titulación de Ushuaia, y se verifica que la fila quedó"
echo " almacenada en el fragmento físico de nodo_ushuaia."
echo ""

contar_titulaciones () {
    local NODO=$1
    echo -n "  $NODO -> "
    docker exec -i $NODO psql -U ezequiel -d untdf_db -t -A -c "$PREAMBULO
SELECT COALESCE(sum(filas), 0) FROM (
    SELECT (xpath('/row/c/text()',
                  query_to_xml('SELECT count(*) AS c FROM public.' ||
                               quote_ident(s.logicalrelid::regclass::text || '_' || s.shardid),
                               false, true, '')
           ))[1]::text::int AS filas
    FROM pg_dist_shard s
    JOIN pg_dist_placement p ON p.shardid = s.shardid
    JOIN pg_dist_node      n ON n.groupid = p.groupid
    WHERE n.nodename = '$NODO'
      AND s.logicalrelid::regclass::text = 'titulaciones'
) t;" | tail -n 1
}

echo " Estado inicial del fragmento de titulaciones en cada nodo:"
contar_titulaciones nodo_ushuaia
contar_titulaciones nodo_riogrande

echo ""
echo " Alta ejecutada desde nodo_riogrande:"
docker exec -i nodo_riogrande psql -U ezequiel -d untdf_db -c "
INSERT INTO titulaciones (id_titulacion, campus, nombre, creditos, nota_minima)
VALUES (99, 'Ushuaia', 'Titulación de prueba remota', 100, 5.00);"

echo ""
echo " Estado posterior. Esperado: nodo_ushuaia pasa de 2 a 3;"
echo " nodo_riogrande permanece en 1."
contar_titulaciones nodo_ushuaia
contar_titulaciones nodo_riogrande

echo ""
echo " Se revierte el alta de prueba desde el coordinador:"
docker exec -i nodo_coordinador psql -U ezequiel -d untdf_db -c "
DELETE FROM titulaciones WHERE id_titulacion = 99 AND campus = 'Ushuaia';"


titulo "FIN DE LAS PRUEBAS POR NODO"
echo ""
echo " Conexión manual a cada servidor de campus:"
echo "   Coordinador : localhost:5532"
echo "   Ushuaia     : localhost:5533"
echo "   Río Grande  : localhost:5534"
echo "   Base untdf_db / usuario ezequiel / contraseña admin"
echo ""
echo " Para ver los fragmentos con \\dt dentro de un worker,"
echo " ejecutar antes:"
echo "   SET citus.override_table_visibility TO false;"
echo ""