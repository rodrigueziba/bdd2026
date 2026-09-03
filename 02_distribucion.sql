-- =========================================================
-- BASES DE DATOS DISTRIBUIDAS - UNTFD
-- DISEÑO DISTRIBUIDO Y ASIGNACIÓN FÍSICA
-- Citus 12.1
-- =========================================================


-- =========================================================
-- 1. REPLICACIÓN TOTAL
-- =========================================================

SELECT create_reference_table('pluses_hijo');

SELECT create_reference_table('clasificaciones');


-- =========================================================
-- 2. FRAGMENTACIÓN HORIZONTAL
-- =========================================================
--
-- Las tablas se distribuyen por CAMPUS.
--
-- Citus utiliza hash-distribution, por lo que el valor
-- 'Ushuaia' o 'Rio Grande' no determina por sí solo
-- el nodo físico.
--
-- =========================================================

SELECT create_distributed_table(
    'titulaciones',
    'campus'
);

SELECT create_distributed_table(
    'cursos',
    'campus'
);

SELECT create_distributed_table(
    'grupos',
    'campus'
);

SELECT create_distributed_table(
    'asignaturas',
    'campus'
);

SELECT create_distributed_table(
    'profesores',
    'campus'
);

SELECT create_distributed_table(
    'imparte',
    'campus'
);


-- =========================================================
-- 3. FRAGMENTACIÓN VERTICAL / HÍBRIDA
-- =========================================================
--
-- PROFESORES se encuentra fragmentada conceptualmente en:
--
--   PROFESORES
--       -> información académica / contacto
--
--   PROFESORES_NOMINA
--       -> información de nómina
--
-- PROFESORES_NOMINA se distribuye por sede_nomina.
--
-- =========================================================

SELECT create_distributed_table(
    'profesores_nomina',
    'sede_nomina'
);


-- =========================================================
-- 4. AISLAMIENTO FÍSICO POR CAMPUS
-- =========================================================
--
-- Debido a la co-localización de las tablas, CASCADE
-- permite aislar también las tablas relacionadas.
--
-- Esto incluye PROFESORES_NOMINA cuando corresponde
-- al grupo de colocación.
--
-- =========================================================


-- ---------------------------------------------------------
-- 4.1 AISLAR USHUAIA
-- ---------------------------------------------------------

SELECT isolate_tenant_to_new_shard(
    'titulaciones',
    'Ushuaia',
    'CASCADE'
);


-- ---------------------------------------------------------
-- 4.2 AISLAR RÍO GRANDE
-- ---------------------------------------------------------

SELECT isolate_tenant_to_new_shard(
    'titulaciones',
    'Rio Grande',
    'CASCADE'
);


-- =========================================================
-- 5. ASIGNACIÓN FÍSICA DEL SHARD DE USHUAIA
-- =========================================================

DO $$
DECLARE
    shard_ushuaia BIGINT;
    nodo_actual TEXT;
BEGIN

    shard_ushuaia :=
        get_shard_id_for_distribution_column(
            'titulaciones',
            'Ushuaia'
        );

    SELECT nodename
    INTO nodo_actual
    FROM citus_shards
    WHERE shardid = shard_ushuaia
    LIMIT 1;

    IF nodo_actual IS NULL THEN
        RAISE EXCEPTION
            'No se encontró el shard de Ushuaia.';
    END IF;

    IF nodo_actual <> 'nodo_ushuaia' THEN

        PERFORM citus_move_shard_placement(
            shard_ushuaia,
            nodo_actual,
            5432,
            'nodo_ushuaia',
            5432
        );

    END IF;

END
$$;


-- =========================================================
-- 6. ASIGNACIÓN FÍSICA DEL SHARD DE RÍO GRANDE
-- =========================================================

DO $$
DECLARE
    shard_rg BIGINT;
    nodo_actual TEXT;
BEGIN

    shard_rg :=
        get_shard_id_for_distribution_column(
            'titulaciones',
            'Rio Grande'
        );

    SELECT nodename
    INTO nodo_actual
    FROM citus_shards
    WHERE shardid = shard_rg
    LIMIT 1;

    IF nodo_actual IS NULL THEN
        RAISE EXCEPTION
            'No se encontró el shard de Río Grande.';
    END IF;

    IF nodo_actual <> 'nodo_riogrande' THEN

        PERFORM citus_move_shard_placement(
            shard_rg,
            nodo_actual,
            5432,
            'nodo_riogrande',
            5432
        );

    END IF;

END
$$;


-- =========================================================
-- 7. RESTRICCIONES DE INTEGRIDAD
-- =========================================================

ALTER TABLE profesores_nomina
    ADD CONSTRAINT fk_nomina_clasif
    FOREIGN KEY (
        id_clasificaciones
    )
    REFERENCES clasificaciones(
        id_clasificaciones
    );


ALTER TABLE profesores_nomina
    ADD CONSTRAINT fk_nomina_pluses
    FOREIGN KEY (
        id_pluses_hijo
    )
    REFERENCES pluses_hijo(
        id_pluses_hijo
    );


-- =========================================================
-- 8. RESTRICCIÓN DE NEGOCIO:
--    HORAS MÁXIMAS POR PROFESOR
-- =========================================================

CREATE OR REPLACE FUNCTION asignar_horas(
    p_id_profesor INT,
    p_id_asignatura INT,
    p_id_curso INT,
    p_id_titulacion INT,
    p_campus VARCHAR,
    p_num_horas INT
)
RETURNS VOID
AS $$
DECLARE
    v_max_horas INT;
    v_horas_actuales INT;
BEGIN

    IF p_num_horas <= 0 THEN
        RAISE EXCEPTION
            'La cantidad de horas debe ser mayor que cero.';
    END IF;


    -- -----------------------------------------------------
    -- Obtener límite de horas del profesor
    -- -----------------------------------------------------

    SELECT c.num_horas_max
    INTO v_max_horas
    FROM profesores_nomina pn
    JOIN clasificaciones c
        ON pn.id_clasificaciones =
           c.id_clasificaciones
    WHERE pn.id_profesor = p_id_profesor;


    IF v_max_horas IS NULL THEN
        RAISE EXCEPTION
            'No se encontró la información de nómina del profesor %.',

            p_id_profesor;
    END IF;


    -- -----------------------------------------------------
    -- Obtener horas actualmente asignadas
    -- -----------------------------------------------------

    SELECT COALESCE(
        SUM(num_horas),
        0
    )
    INTO v_horas_actuales
    FROM imparte
    WHERE id_profesor = p_id_profesor
      AND campus = p_campus;


    -- -----------------------------------------------------
    -- Validar límite
    -- -----------------------------------------------------

    IF (
        v_horas_actuales + p_num_horas
    ) > v_max_horas THEN

        RAISE EXCEPTION
            'El profesor supera el límite de horas máximas. (Límite: %, Intento acumulado: %)',
            v_max_horas,
            (
                v_horas_actuales
                + p_num_horas
            );

    END IF;


    -- -----------------------------------------------------
    -- Insertar asignación
    -- -----------------------------------------------------

    INSERT INTO imparte (
        id_profesor,
        id_asignatura,
        id_curso,
        id_titulacion,
        campus,
        num_horas
    )
    VALUES (
        p_id_profesor,
        p_id_asignatura,
        p_id_curso,
        p_id_titulacion,
        p_campus,
        p_num_horas
    );

END;
$$ LANGUAGE plpgsql;