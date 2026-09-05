-- =========================================================
-- BASES DE DATOS DISTRIBUIDAS - UNTDF
-- 04 - PRUEBAS DE VALIDACIÓN (desde el COORDINADOR)
-- =========================================================
-- Ejecutar con:
--   docker exec -it nodo_coordinador psql -U ezequiel -d untdf_db
-- y pegar cada prueba, o bien de corrido con:
--   docker exec -i nodo_coordinador psql -U ezequiel -d untdf_db < 04_pruebas.sql
--
-- Las pruebas 8 y 9 PRODUCEN UN ERROR A PROPÓSITO. Ese error
-- es el resultado esperado, no una falla del despliegue.
--
-- Las pruebas que requieren conectarse a cada worker están
-- en el guión 05_pruebas_nodos.sh
-- =========================================================


\echo ''
\echo '========================================================='
\echo ' PRUEBA 1 - TRANSPARENCIA DE LOCALIZACIÓN'
\echo '========================================================='
\echo ' Objetivo: el usuario consulta una sola tabla lógica sin'
\echo ' saber que está partida en dos servidores físicos.'
\echo ' Esperado: 5 profesores, de ambas sedes, en un resultado'
\echo ' único.'
\echo ''

SELECT id_profesor, nombre, campus, email
FROM profesores
ORDER BY campus, id_profesor;


\echo ''
\echo '========================================================='
\echo ' PRUEBA 2 - METADATOS: DÓNDE DICE CITUS QUE ESTÁN'
\echo '========================================================='
\echo ' Objetivo: mostrar que de los 36 fragmentos de cada tabla'
\echo ' solo 2 fueron aislados y asignados explícitamente.'
\echo ' (32 por defecto, mas dos que agrega cada aislamiento)'
\echo ' Esperado: fragmento de Ushuaia en nodo_ushuaia y el de'
\echo ' Río Grande en nodo_riogrande.'
\echo ''

SELECT
    'Ushuaia' AS sede,
    get_shard_id_for_distribution_column('titulaciones', 'Ushuaia') AS shardid,
    (SELECT nodename FROM citus_shards
      WHERE shardid = get_shard_id_for_distribution_column('titulaciones','Ushuaia')
      LIMIT 1) AS nodo
UNION ALL
SELECT
    'Rio Grande',
    get_shard_id_for_distribution_column('titulaciones', 'Rio Grande'),
    (SELECT nodename FROM citus_shards
      WHERE shardid = get_shard_id_for_distribution_column('titulaciones','Rio Grande')
      LIMIT 1);


\echo ''
\echo '========================================================='
\echo ' PRUEBA 3 - UBICACIÓN FÍSICA REAL DE LAS FILAS'
\echo '========================================================='
\echo ' ESTA ES LA PRUEBA CENTRAL DEL TRABAJO.'
\echo ''
\echo ' run_command_on_placements ejecuta la consulta contra el'
\echo ' fragmento FÍSICO (por ejemplo profesores_102247), que es'
\echo ' una tabla PostgreSQL común dentro de un nodo concreto. No'
\echo ' hay ruteo distribuido posible: lo que devuelve es'
\echo ' literalmente lo que hay en ese disco.'
\echo ''
\echo ' Esperado (solo fragmentos no vacíos):'
\echo '   nodo_ushuaia   -> titulaciones 2, cursos 3, grupos 4,'
\echo '                     asignaturas 4, profesores 3,'
\echo '                     imparte 4, nomina 5'
\echo '   nodo_riogrande -> titulaciones 1, cursos 1, grupos 1,'
\echo '                     asignaturas 3, profesores 2,'
\echo '                     imparte 2, nomina 0'
\echo ''

SELECT 'titulaciones' AS tabla, nodename AS nodo, shardid, result AS filas
  FROM run_command_on_placements('titulaciones', $cmd$ SELECT count(*) FROM %s $cmd$)
 WHERE result <> '0'
UNION ALL
SELECT 'cursos', nodename, shardid, result
  FROM run_command_on_placements('cursos', $cmd$ SELECT count(*) FROM %s $cmd$)
 WHERE result <> '0'
UNION ALL
SELECT 'grupos', nodename, shardid, result
  FROM run_command_on_placements('grupos', $cmd$ SELECT count(*) FROM %s $cmd$)
 WHERE result <> '0'
UNION ALL
SELECT 'asignaturas', nodename, shardid, result
  FROM run_command_on_placements('asignaturas', $cmd$ SELECT count(*) FROM %s $cmd$)
 WHERE result <> '0'
UNION ALL
SELECT 'profesores', nodename, shardid, result
  FROM run_command_on_placements('profesores', $cmd$ SELECT count(*) FROM %s $cmd$)
 WHERE result <> '0'
UNION ALL
SELECT 'imparte', nodename, shardid, result
  FROM run_command_on_placements('imparte', $cmd$ SELECT count(*) FROM %s $cmd$)
 WHERE result <> '0'
UNION ALL
SELECT 'profesores_nomina', nodename, shardid, result
  FROM run_command_on_placements('profesores_nomina', $cmd$ SELECT count(*) FROM %s $cmd$)
 WHERE result <> '0'
ORDER BY nodo, tabla;


\echo ''
\echo '========================================================='
\echo ' PRUEBA 4 - CONTRAPRUEBA: POR QUÉ NO SIRVE'
\echo '            run_command_on_workers PARA ESTO'
\echo '========================================================='
\echo ' Desde Citus 11 los metadatos se sincronizan en todos los'
\echo ' nodos. Si se le envía "SELECT count(*) FROM profesores"'
\echo ' a un worker, éste NO cuenta lo suyo: lo resuelve como'
\echo ' consulta distribuida global y devuelve el total.'
\echo ''
\echo ' Esperado: AMBOS nodos responden 5 (no 3 y 2).'
\echo ' Por eso la prueba válida es la nro 3.'
\echo ''

SELECT nodename AS nodo, result AS respuesta
FROM run_command_on_workers('SELECT count(*) FROM profesores');


\echo ''
\echo '========================================================='
\echo ' PRUEBA 5 - REPLICACIÓN TOTAL DE LOS CATÁLOGOS'
\echo '========================================================='
\echo ' Objetivo: verificar que PLUSES_HIJO y CLASIFICACIONES'
\echo ' existen completas y sincronizadas en cada nodo.'
\echo ' Esperado: 3 filas de cada catálogo en cada ubicación.'
\echo ' Aparecen tres nodos y no dos: el coordinador también'
\echo ' mantiene una copia de las tablas de referencia, porque'
\echo ' fue registrado en los metadatos del clúster.'
\echo ' Ningún nodo necesita pedirle esta información al otro.'
\echo ''

SELECT 'pluses_hijo' AS tabla, nodename AS nodo, result AS filas
  FROM run_command_on_placements('pluses_hijo', $cmd$ SELECT count(*) FROM %s $cmd$)
UNION ALL
SELECT 'clasificaciones', nodename, result
  FROM run_command_on_placements('clasificaciones', $cmd$ SELECT count(*) FROM %s $cmd$)
ORDER BY tabla, nodo;

SELECT table_name, citus_table_type, distribution_column, shard_count
FROM citus_tables
ORDER BY citus_table_type, table_name;


\echo ''
\echo '========================================================='
\echo ' PRUEBA 6 - FRAGMENTACIÓN HÍBRIDA DE PROFESORES'
\echo '========================================================='
\echo ' 6.a  LA REUNIÓN NO ES CO-LOCALIZADA  <<< SE ESPERA UN ERROR >>>'
\echo ''
\echo ' Se intenta cruzar los datos de contacto con los de'
\echo ' nómina. PROFESORES se fragmenta por campus y'
\echo ' PROFESORES_NOMINA por sede_nomina, pero el JOIN es por'
\echo ' id_profesor, que no es clave de distribución de ninguna'
\echo ' de las dos. Citus no puede resolverlo localmente.'
\echo ''
\echo ' Esperado: ERROR "the query contains a join that requires'
\echo ' repartitioning". Ese error ES la demostración de que la'
\echo ' fragmentación vertical separó los datos en dos grupos'
\echo ' que no se pueden reunir sin mover tuplas entre nodos.'
\echo ''

SELECT p.id_profesor, p.nombre, p.campus, n.sede_nomina, c.categoria
FROM profesores p
JOIN profesores_nomina n ON p.id_profesor = n.id_profesor
JOIN clasificaciones  c ON n.id_clasificaciones = c.id_clasificaciones
ORDER BY p.campus, p.id_profesor;

\echo ''
\echo ' 6.b  LA MISMA CONSULTA, AUTORIZANDO EL REPARTICIONAMIENTO'
\echo ''
\echo ' Objetivo: los datos de CONTACTO viven en la sede del'
\echo ' docente, pero los de NÓMINA están todos en Ushuaia.'
\echo ' Esperado: Nadia Ramos y Marta Silva son de Río Grande'
\echo ' y aun así su nómina figura con sede_nomina = Ushuaia.'
\echo ''
\echo ' Se requieren DOS autorizaciones, no una:'
\echo ''
\echo '  - enable_repartition_joins habilita el movimiento de'
\echo '    tuplas entre nodos que exige la reunión.'
\echo ''
\echo '  - multi_shard_modify_mode = sequential es necesario'
\echo '    porque PROFESORES_NOMINA tiene una clave foránea'
\echo '    hacia la tabla de referencia CLASIFICACIONES. El'
\echo '    reparticionamiento crea resultados intermedios en'
\echo '    cada nodo, y Citus exige resolverlos con una única'
\echo '    conexión por nodo para no romper la integridad'
\echo '    referencial contra una tabla replicada.'
\echo ''
\echo ' Es otra manifestación del mismo costo: la reunión entre'
\echo ' fragmentos verticales no solo mueve datos por la red,'
\echo ' además pierde el paralelismo entre fragmentos.'
\echo ''

SET citus.enable_repartition_joins = on;

BEGIN;
SET LOCAL citus.multi_shard_modify_mode TO 'sequential';

SELECT p.id_profesor,
       p.nombre,
       p.campus        AS sede_contacto,
       n.sede_nomina   AS sede_nomina,
       c.categoria,
       c.num_horas_max
FROM profesores p
JOIN profesores_nomina n ON p.id_profesor = n.id_profesor
JOIN clasificaciones  c ON n.id_clasificaciones = c.id_clasificaciones
ORDER BY p.campus, p.id_profesor;

COMMIT;


\echo ''
\echo '========================================================='
\echo ' PRUEBA 7 - COSTO DE LA FRAGMENTACIÓN VERTICAL'
\echo '========================================================='
\echo ' Se examina el plan de ejecución de la consulta anterior.'
\echo ''
\echo ' Esperado: un árbol con nodos MapMergeJob, que es la'
\echo ' forma en que Citus expresa una reunión con'
\echo ' reparticionamiento: primero redistribuye las tuplas'
\echo ' entre los nodos (Map) y después las combina (Merge).'
\echo ''
\echo ' Obsérvese que Map Task Count coincide con el número de'
\echo ' fragmentos de la relación distribuida.'
\echo ''
\echo ' Conclusión de diseño: aislar la nómina en Ushuaia cumple'
\echo ' el requerimiento, pero tiene como contrapartida tráfico'
\echo ' de red en toda consulta que cruce contacto con salario.'
\echo ''

EXPLAIN (COSTS OFF)
SELECT p.nombre, p.campus, n.sede_nomina, c.categoria
FROM profesores p
JOIN profesores_nomina n ON p.id_profesor = n.id_profesor
JOIN clasificaciones  c ON n.id_clasificaciones = c.id_clasificaciones
WHERE p.campus = 'Ushuaia';


\echo ''
\echo '========================================================='
\echo ' PRUEBA 8 - RESTRICCIÓN DE HORAS MÁXIMAS'
\echo '========================================================='
\echo ' 8.a  CASO VÁLIDO'
\echo ' Nadia Ramos (201) es Adjunto Simple: máximo 10 horas.'
\echo ' Tiene 8 asignadas. Se le agregan 2 -> total 10.'
\echo ' Esperado: la asignación se acepta.'
\echo ''

SELECT asignar_horas(201, 7, 1, 2, 'Rio Grande', 2);

SELECT id_profesor, sum(num_horas) AS horas_asignadas
FROM imparte WHERE id_profesor = 201 GROUP BY id_profesor;

\echo ''
\echo ' Se revierte para dejar el estado inicial:'
DELETE FROM imparte
WHERE id_profesor = 201 AND id_asignatura = 7
  AND id_curso = 1 AND id_titulacion = 2 AND campus = 'Rio Grande';

\echo ''
\echo ' 8.b  CASO INVÁLIDO  <<< SE ESPERA UN ERROR >>>'
\echo ' Se intenta agregar 4 horas: 8 + 4 = 12 > 10.'
\echo ' Esperado: ERROR con el mensaje personalizado.'
\echo ''

SELECT asignar_horas(201, 7, 1, 2, 'Rio Grande', 4);


\echo ''
\echo '========================================================='
\echo ' PRUEBA 9 - CLAVE ALTERNATIVA: EMAIL ÚNICO'
\echo '========================================================='
\echo ' Se intenta dar de alta un docente en Ushuaia con un'
\echo ' correo que ya existe en esa sede.'
\echo ' Esperado: ERROR duplicate key value violates unique'
\echo ' constraint. El nodo de Ushuaia lo rechaza por sí mismo.'
\echo ''

INSERT INTO profesores (id_profesor, campus, nombre, direccion, telefono, email, despacho)
VALUES (104, 'Ushuaia', 'Andres Parson', 'Calle 1', '29019999',
        'aparson@untdf.edu.ar', 'DESP004');


\echo ''
\echo '========================================================='
\echo ' PRUEBA 10 - RESTRICCIONES DE DOMINIO  <<< ERRORES >>>'
\echo '========================================================='
\echo ' 10.a Teléfono con prefijo de la otra sede.'
\echo ' Esperado: ERROR de CHECK (2964 no es válido en Ushuaia).'
\echo ''

INSERT INTO profesores (id_profesor, campus, nombre, direccion, telefono, email, despacho)
VALUES (105, 'Ushuaia', 'Juan Perez', 'Calle 2', '29641234',
        'jperez@untdf.edu.ar', 'DESP005');

\echo ''
\echo ' 10.b Turno fuera del dominio permitido.'
\echo ' Esperado: ERROR de CHECK.'
\echo ''

INSERT INTO grupos (id_grupo, id_curso, id_titulacion, campus, turno)
VALUES (9, 1, 1, 'Ushuaia', 'MADRUGADA');


\echo ''
\echo '========================================================='
\echo ' PRUEBA 11 - CURSOS COMO ENTIDAD DÉBIL'
\echo '========================================================='
\echo ' Objetivo: demostrar que el mismo número de curso puede'
\echo ' repetirse en titulaciones distintas.'
\echo ' Esperado: el curso 1 aparece en las titulaciones 1, 2 y'
\echo ' 3. Las titulaciones 1 y 3 son ambas de Ushuaia, con lo'
\echo ' cual la unicidad no la da el campus sino id_titulacion.'
\echo ''

SELECT c.id_curso, c.id_titulacion, t.nombre AS titulacion, c.campus, c.max_alumnos
FROM cursos c
JOIN titulaciones t
  ON c.id_titulacion = t.id_titulacion AND c.campus = t.campus
ORDER BY c.id_curso, c.id_titulacion;

\echo ''
\echo ' Y el borrado en cascada desde la entidad fuerte:'
\echo ' (solo se muestra el conteo dependiente, no se borra)'
\echo ''

SELECT t.id_titulacion, t.nombre, t.campus,
       count(DISTINCT c.id_curso) AS cursos,
       count(DISTINCT a.id_asignatura) AS asignaturas
FROM titulaciones t
LEFT JOIN cursos c
       ON c.id_titulacion = t.id_titulacion AND c.campus = t.campus
LEFT JOIN asignaturas a
       ON a.id_titulacion = t.id_titulacion AND a.campus = t.campus
GROUP BY t.id_titulacion, t.nombre, t.campus
ORDER BY t.campus, t.id_titulacion;

\echo ''
\echo '========================================================='
\echo ' FIN DE LAS PRUEBAS DEL COORDINADOR'
\echo ' Continuar con:  ./05_pruebas_nodos.sh'
\echo '========================================================='