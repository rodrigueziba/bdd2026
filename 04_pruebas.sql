-- =========================================================
-- PRUEBAS DE VALIDACIÓN
-- =========================================================


-- =========================================================
-- PRUEBA 1
-- Transparencia de localización
-- =========================================================

SELECT
    nombre,
    campus,
    email
FROM profesores
ORDER BY campus;


-- =========================================================
-- PRUEBA 2
-- Verificar dónde están físicamente los shards
--
-- Esta consulta se ejecuta en el COORDINADOR y consulta
-- directamente los metadatos de Citus.
-- =========================================================

SELECT
    table_name,
    shardid,
    shard_name,
    nodename,
    nodeport
FROM citus_shards
WHERE table_name IN (
    'titulaciones',
    'cursos',
    'grupos',
    'asignaturas',
    'profesores',
    'imparte',
    'profesores_nomina'
)
ORDER BY
    table_name,
    shardid;


-- =========================================================
-- PRUEBA 3
-- Verificar específicamente el shard de Ushuaia
-- =========================================================

SELECT
    'TITULACIONES - USHUAIA' AS prueba,
    get_shard_id_for_distribution_column(
        'titulaciones',
        'Ushuaia'
    ) AS shardid;


SELECT
    table_name,
    shardid,
    nodename
FROM citus_shards
WHERE shardid =
    get_shard_id_for_distribution_column(
        'titulaciones',
        'Ushuaia'
    );


-- =========================================================
-- PRUEBA 4
-- Verificar específicamente el shard de Río Grande
-- =========================================================

SELECT
    'TITULACIONES - RIO GRANDE' AS prueba,
    get_shard_id_for_distribution_column(
        'titulaciones',
        'Rio Grande'
    ) AS shardid;


SELECT
    table_name,
    shardid,
    nodename
FROM citus_shards
WHERE shardid =
    get_shard_id_for_distribution_column(
        'titulaciones',
        'Rio Grande'
    );


-- =========================================================
-- PRUEBA 5
-- Verificar ubicación física de PROFESORES_NOMINA
-- =========================================================

SELECT
    table_name,
    shardid,
    shard_name,
    nodename,
    nodeport
FROM citus_shards
WHERE table_name = 'profesores_nomina';


-- =========================================================
-- PRUEBA 6
-- Verificar replicación
-- =========================================================

SELECT
    table_name,
    citus_table_type
FROM citus_tables
WHERE table_name IN (
    'pluses_hijo',
    'clasificaciones'
);


-- =========================================================
-- PRUEBA 7
-- JOIN entre fragmento de contacto y nómina
-- =========================================================

SET citus.enable_repartition_joins = on;

SELECT
    p.nombre,
    p.campus,
    n.sede_nomina,
    c.categoria,
    c.num_horas_max
FROM profesores p

JOIN profesores_nomina n
    ON p.id_profesor = n.id_profesor

JOIN clasificaciones c
    ON n.id_clasificaciones =
       c.id_clasificaciones

WHERE p.campus = 'Ushuaia';


-- =========================================================
-- PRUEBA 8
-- Restricción de horas máximas
-- =========================================================
--
-- Nadia tiene:
--
-- máximo = 10
-- actual = 8
--
-- Intentamos agregar 4.
--
-- Resultado esperado:
-- ERROR
-- =========================================================

SELECT asignar_horas(
    201,
    3,
    1,
    2,
    'Rio Grande',
    4
);


-- =========================================================
-- PRUEBA 9
-- UNIQUE de email
-- =========================================================

INSERT INTO profesores (
    id_profesor,
    campus,
    nombre,
    direccion,
    telefono,
    email,
    despacho
)
VALUES (
    102,
    'Ushuaia',
    'Segundo Parson',
    'Calle 1',
    '29019999',
    'aparson@untdf.edu.ar',
    'DESP003'
);


-- =========================================================
-- PRUEBA 10
-- Entidad débil CURSOS
-- =========================================================
--
-- Debe ser posible tener:
--
-- Curso 1 / Titulación 1
-- Curso 1 / Titulación 2
--
-- porque CURSOS depende de TITULACIONES.
-- =========================================================

SELECT
    id_curso,
    id_titulacion,
    campus,
    max_alumnos
FROM cursos
ORDER BY
    id_titulacion;