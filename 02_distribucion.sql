-- =========================================================
 DISEÑO DISTRIBUIDO Y ASIGNACIÓN EXPLÍCITA
-- =========================================================

-- 1. Replicación Total de Catálogos
SELECT create_reference_table('pluses_hijo');
SELECT create_reference_table('clasificaciones');

-- 2. Fragmentación Horizontal (Tablas de Negocio)
SELECT create_distributed_table('titulaciones', 'campus');
SELECT create_distributed_table('cursos', 'campus');
SELECT create_distributed_table('grupos', 'campus');
SELECT create_distributed_table('asignaturas', 'campus');
SELECT create_distributed_table('profesores', 'campus');
SELECT create_distributed_table('imparte', 'campus');

-- 3. Fragmentación Vertical (Nómina alojada íntegramente en Ushuaia)
SELECT create_distributed_table('profesores_nomina', 'sede_nomina');

-- =========================================================
-- ASIGNACIÓN EXPLÍCITA Y AISLAMIENTO
-- =========================================================
-- Al usar CASCADE, Citus aísla automáticamente todas las tablas co-localizadas
SELECT isolate_tenant_to_new_shard('titulaciones', 'Ushuaia', 'CASCADE');
SELECT isolate_tenant_to_new_shard('titulaciones', 'Rio Grande', 'CASCADE');

-- Forzamos el movimiento físico a los nodos correctos
DO $$
DECLARE
    shard_ushuaia bigint;
    shard_rg bigint;
    nodo_actual text;
BEGIN
    shard_ushuaia := get_shard_id_for_distribution_column('titulaciones', 'Ushuaia');
    SELECT nodename INTO nodo_actual FROM citus_shards WHERE shardid = shard_ushuaia LIMIT 1;
    IF nodo_actual != 'nodo_ushuaia' THEN
        PERFORM citus_move_shard_placement(shard_ushuaia, nodo_actual, 5432, 'nodo_ushuaia', 5432);
    END IF;

    shard_rg := get_shard_id_for_distribution_column('titulaciones', 'Rio Grande');
    SELECT nodename INTO nodo_actual FROM citus_shards WHERE shardid = shard_rg LIMIT 1;
    IF nodo_actual != 'nodo_riogrande' THEN
        PERFORM citus_move_shard_placement(shard_rg, nodo_actual, 5432, 'nodo_riogrande', 5432);
    END IF;
END $$;

-- =========================================================
-- RESTRICCIÓN DE NEGOCIO: HORAS MÁXIMAS POR PROFESOR
-- Implementado como Función (Stored Procedure) por restricciones de Citus
-- =========================================================

CREATE OR REPLACE FUNCTION asignar_horas(
    p_id_profesor INT,
    p_id_asignatura INT,
    p_id_curso INT,
    p_id_titulacion INT,
    p_campus VARCHAR,
    p_num_horas INT
) RETURNS VOID AS $$
DECLARE
    v_max_horas INT;
    v_horas_actuales INT;
BEGIN
    -- 1. Obtener límite
    SELECT c.num_horas_max INTO v_max_horas
    FROM profesores_nomina pn
    JOIN clasificaciones c ON pn.id_clasificaciones = c.id_clasificaciones
    WHERE pn.id_profesor = p_id_profesor;

    -- 2. Obtener horas actuales
    SELECT COALESCE(SUM(num_horas), 0) INTO v_horas_actuales
    FROM imparte
    WHERE id_profesor = p_id_profesor AND campus = p_campus;

    -- 3. Validar
    IF (v_horas_actuales + p_num_horas) > v_max_horas THEN
        RAISE EXCEPTION 'El profesor supera el límite de horas máximas. (Límite: %, Intento acumulado: %)', v_max_horas, (v_horas_actuales + p_num_horas);
    END IF;

    -- 4. Insertar si es válido
    INSERT INTO imparte (id_profesor, id_asignatura, id_curso, id_titulacion, campus, num_horas)
    VALUES (p_id_profesor, p_id_asignatura, p_id_curso, p_id_titulacion, p_campus, p_num_horas);
END;

ALTER TABLE profesores_nomina 
  ADD CONSTRAINT fk_nomina_clasif 
  FOREIGN KEY (id_clasificaciones) REFERENCES clasificaciones(id_clasificaciones);

ALTER TABLE profesores_nomina 
  ADD CONSTRAINT fk_nomina_pluses 
  FOREIGN KEY (id_pluses_hijo) REFERENCES pluses_hijo(id_pluses_hijo);

$$ LANGUAGE plpgsql;