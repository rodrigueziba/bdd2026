#!/bin/bash
# =========================================================
# BASES DE DATOS DISTRIBUIDAS - UNTDF
# 05 - PRUEBAS EJECUTADAS DENTRO DE CADA NODO
# =========================================================
# Estas pruebas no pasan por el coordinador: se conectan
# directamente a cada servidor de campus
# =========================================================

set -u

titulo () {
    echo ""
    echo "========================================================="
    echo " $1"
    echo "========================================================="
}

# Consulta que lista las tablas-fragmento FÍSICAS presentes en
# el nodo y cuenta sus filas reales. Son tablas PostgreSQL
# comunes: no interviene el planificador distribuido.
SQL_FRAGMENTOS="
SELECT c.relname AS fragmento_fisico,
       (xpath('/row/c/text()',
              query_to_xml('SELECT count(*) AS c FROM public.'||quote_ident(c.relname),
                           false, true, '')))[1]::text::int AS filas_reales
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
  AND c.relname ~ '^(titulaciones|cursos|grupos|asignaturas|profesores|imparte|profesores_nomina)_[0-9]+\$'
ORDER BY 1;
"


titulo "PRUEBA A - QUÉ HAY FÍSICAMENTE EN nodo_ushuaia"
echo " Esperado: fragmentos con datos de la sede Ushuaia."
echo "   titulaciones 2 | cursos 3 | grupos 4 | asignaturas 4"
echo "   profesores 3   | imparte 4 | profesores_nomina 5"
echo " Los demás fragmentos aparecen con 0 filas."
echo ""
docker exec -i nodo_ushuaia psql -U ezequiel -d untdf_db \
    -c "$SQL_FRAGMENTOS" | grep -v " 0$" || true


titulo "PRUEBA B - QUÉ HAY FÍSICAMENTE EN nodo_riogrande"
echo " Esperado: fragmentos con datos de la sede Río Grande."
echo "   titulaciones 1 | cursos 1 | grupos 1 | asignaturas 3"
echo "   profesores 2   | imparte 2 | profesores_nomina AUSENTE"
echo ""
echo " La nómina NO debe aparecer con filas en este nodo: ese"
echo " es el fragmento vertical alojado en Ushuaia."
echo ""
docker exec -i nodo_riogrande psql -U ezequiel -d untdf_db \
    -c "$SQL_FRAGMENTOS" | grep -v " 0$" || true


titulo "PRUEBA C - CONTENIDO REAL DEL FRAGMENTO DE CADA SEDE"
echo " Se lee el fragmento físico de profesores en cada nodo."
echo " Esperado: Ushuaia muestra 3 docentes de Ushuaia y"
echo " Río Grande muestra 2 de Río Grande. Ningún cruce."
echo ""
echo "--- nodo_ushuaia ---"
docker exec -i nodo_ushuaia psql -U ezequiel -d untdf_db -c "
DO \$\$
DECLARE r RECORD; frag TEXT;
BEGIN
  SELECT c.relname INTO frag
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind='r'
    AND c.relname ~ '^profesores_[0-9]+\$'
    AND (xpath('/row/c/text()', query_to_xml('SELECT count(*) AS c FROM public.'||quote_ident(c.relname),false,true,'')))[1]::text::int > 0
  LIMIT 1;
  RAISE NOTICE 'Fragmento fisico: %', frag;
  FOR r IN EXECUTE 'SELECT id_profesor, nombre, campus FROM public.'||quote_ident(frag) LOOP
    RAISE NOTICE '  % | % | %', r.id_profesor, r.nombre, r.campus;
  END LOOP;
END \$\$;"

echo ""
echo "--- nodo_riogrande ---"
docker exec -i nodo_riogrande psql -U ezequiel -d untdf_db -c "
DO \$\$
DECLARE r RECORD; frag TEXT;
BEGIN
  SELECT c.relname INTO frag
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind='r'
    AND c.relname ~ '^profesores_[0-9]+\$'
    AND (xpath('/row/c/text()', query_to_xml('SELECT count(*) AS c FROM public.'||quote_ident(c.relname),false,true,'')))[1]::text::int > 0
  LIMIT 1;
  RAISE NOTICE 'Fragmento fisico: %', frag;
  FOR r IN EXECUTE 'SELECT id_profesor, nombre, campus FROM public.'||quote_ident(frag) LOOP
    RAISE NOTICE '  % | % | %', r.id_profesor, r.nombre, r.campus;
  END LOOP;
END \$\$;"


titulo "PRUEBA D - CATÁLOGOS REPLICADOS PRESENTES EN CADA NODO"
echo " Las Reference Tables se guardan con su nombre de tabla"
echo " más el identificador de fragmento, y existen en todos"
echo " los nodos. Esperado: 3 filas en cada uno, leídas en"
echo " forma local, sin consultar al otro nodo."
echo ""
for NODO in nodo_ushuaia nodo_riogrande; do
    echo "--- $NODO ---"
    docker exec -i $NODO psql -U ezequiel -d untdf_db -t -c "
    SELECT c.relname,
           (xpath('/row/c/text()',
                  query_to_xml('SELECT count(*) AS c FROM public.'||quote_ident(c.relname),
                               false,true,'')))[1]::text::int AS filas
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relkind='r'
      AND c.relname ~ '^(pluses_hijo|clasificaciones)_[0-9]+\$';"
done


titulo "PRUEBA E - ACCESO A LOS DATOS DE USHUAIA DESDE RÍO GRANDE"
echo " Requerimiento de la consigna. Nos conectamos al servidor"
echo " de Río Grande y consultamos datos que están físicamente"
echo " en Ushuaia. Citus resuelve el acceso remoto de forma"
echo " transparente."
echo " Esperado: los 3 docentes de Ushuaia."
echo ""
docker exec -i nodo_riogrande psql -U ezequiel -d untdf_db -c "
SELECT id_profesor, nombre, campus FROM profesores WHERE campus = 'Ushuaia' ORDER BY id_profesor;"


titulo "PRUEBA F - ACCESO A LOS DATOS DE RÍO GRANDE DESDE USHUAIA"
echo " El requerimiento simétrico."
echo " Esperado: los 2 docentes de Río Grande."
echo ""
docker exec -i nodo_ushuaia psql -U ezequiel -d untdf_db -c "
SELECT id_profesor, nombre, campus FROM profesores WHERE campus = 'Rio Grande' ORDER BY id_profesor;"


titulo "PRUEBA G - ESCRITURA DESDE UNA SEDE SOBRE LA OTRA"
echo " Se da de alta desde el servidor de Río Grande una"
echo " titulación de Ushuaia, y se verifica que la fila quedó"
echo " almacenada en el fragmento físico de nodo_ushuaia."
echo ""
docker exec -i nodo_riogrande psql -U ezequiel -d untdf_db -c "
INSERT INTO titulaciones (id_titulacion, campus, nombre, creditos, nota_minima)
VALUES (99, 'Ushuaia', 'Titulación de prueba remota', 100, 5.00);"

echo ""
echo " Conteo del fragmento físico de titulaciones en cada nodo."
echo " Esperado: nodo_ushuaia pasa de 2 a 3; nodo_riogrande sigue en 1."
echo ""
for NODO in nodo_ushuaia nodo_riogrande; do
    echo -n "  $NODO -> "
    docker exec -i $NODO psql -U ezequiel -d untdf_db -t -A -c "
    SELECT coalesce(sum((xpath('/row/c/text()',
             query_to_xml('SELECT count(*) AS c FROM public.'||quote_ident(c.relname),
                          false,true,'')))[1]::text::int),0)
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relkind='r'
      AND c.relname ~ '^titulaciones_[0-9]+\$';"
done

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