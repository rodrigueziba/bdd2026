-- =========================================================
-- BASES DE DATOS DISTRIBUIDAS - UNTDF
-- 02 - DISEÑO DISTRIBUIDO Y ASIGNACIÓN FÍSICA
-- Citus 12.1
-- =========================================================


-- =========================================================
-- 1. REPLICACIÓN TOTAL  (Reference Tables)
-- =========================================================
-- PLUSES_HIJO y CLASIFICACIONES tienen baja tasa de
-- actualización y alta disponibilidad requerida, y el
-- enunciado pide explícitamente que estén replicadas.
-- Una Reference Table mantiene una copia íntegra y
-- sincronizada en TODOS los nodos del clúster.
-- =========================================================

SELECT create_reference_table('pluses_hijo');
SELECT create_reference_table('clasificaciones');


-- =========================================================
-- 2. FRAGMENTACIÓN HORIZONTAL POR CAMPUS
-- =========================================================
-- create_distributed_table(tabla, 'campus') NO coloca los
-- datos de Ushuaia en nodo_ushuaia. Lo que hace es:
--   a) partir la tabla en 32 fragmentos (shard_count por
--      defecto),
--   b) asignar cada fila al fragmento nro hash(campus) % 32,
--   c) repartir esos 32 fragmentos entre los workers sin
--      mirar el VALOR de la clave.
--
-- Es decir: la ubicación física es arbitraria. Para cumplir
-- el requerimiento de que cada sede aloje sus propios datos
-- hace falta la asignación explícita de los pasos 3 y 4.
--
-- colocate_with se declara de forma explícita para que las
-- siete tablas queden en el MISMO grupo de co-localización.
-- Sin esto la co-localización ocurriría igual (por tener el
-- mismo tipo de columna de distribución y el mismo número de
-- fragmentos), pero de manera implícita y frágil.
-- =========================================================

SELECT create_distributed_table('titulaciones', 'campus');

SELECT create_distributed_table('cursos',      'campus', colocate_with => 'titulaciones');
SELECT create_distributed_table('grupos',      'campus', colocate_with => 'titulaciones');
SELECT create_distributed_table('asignaturas', 'campus', colocate_with => 'titulaciones');
SELECT create_distributed_table('profesores',  'campus', colocate_with => 'titulaciones');
SELECT create_distributed_table('imparte',     'campus', colocate_with => 'titulaciones');


-- ---------------------------------------------------------
-- Fragmento vertical de la nómina.
--
-- Se distribuye por sede_nomina y se co-localiza con el
-- resto. Como sede_nomina solo admite 'Ushuaia' (CHECK del
-- esquema) y hash('Ushuaia') es el mismo valor cualquiera
-- sea el nombre de la columna, TODAS las filas de nómina
-- caen en el mismo grupo de fragmentos que los datos de
-- Ushuaia, y por lo tanto viajan con ellos al nodo correcto.
-- ---------------------------------------------------------

SELECT create_distributed_table('profesores_nomina', 'sede_nomina', colocate_with => 'titulaciones');


-- =========================================================
-- 3. AISLAMIENTO DE CADA SEDE EN SU PROPIO FRAGMENTO
-- =========================================================
-- isolate_tenant_to_new_shard parte el fragmento que
-- contiene el valor indicado y deja un fragmento NUEVO que
-- contiene únicamente ese valor.
--
-- Con 'CASCADE' la operación se aplica a todas las tablas
-- co-localizadas, no solo a titulaciones.
--
-- Cada aislamiento parte un fragmento en hasta TRES: el
-- rango anterior al valor aislado, el fragmento del valor
-- aislado y el rango posterior. El total pasa entonces de
-- 32 a 34 con la primera llamada y a 36 con la segunda.
--
-- Resultado: de los 36 fragmentos, 2 concentran el 100% de
-- los datos (uno por sede) y los 34 restantes quedan vacíos.
-- =========================================================

SELECT isolate_tenant_to_new_shard('titulaciones', 'Ushuaia',    'CASCADE');
SELECT isolate_tenant_to_new_shard('titulaciones', 'Rio Grande', 'CASCADE');


-- =========================================================
-- 4. ASIGNACIÓN FÍSICA EXPLÍCITA A CADA NODO
-- =========================================================
-- citus_move_shard_placement mueve el fragmento indicado y
-- TODOS sus fragmentos co-localizados al nodo destino.
-- Requiere wal_level=logical (definido en docker-compose).
-- =========================================================

-- ---------------------------------------------------------
-- 4.1  Fragmento de Ushuaia  ->  nodo_ushuaia
-- ---------------------------------------------------------

DO $$
DECLARE
    v_shard  BIGINT;
    v_nodo   TEXT;
BEGIN
    v_shard := get_shard_id_for_distribution_column('titulaciones', 'Ushuaia');

    SELECT nodename INTO v_nodo
    FROM citus_shards
    WHERE shardid = v_shard
    LIMIT 1;

    IF v_nodo IS NULL THEN
        RAISE EXCEPTION 'No se encontró el fragmento de Ushuaia.';
    END IF;

    IF v_nodo <> 'nodo_ushuaia' THEN
        RAISE NOTICE 'Moviendo fragmento % de % a nodo_ushuaia', v_shard, v_nodo;
        PERFORM citus_move_shard_placement(v_shard, v_nodo, 5432, 'nodo_ushuaia', 5432);
    ELSE
        RAISE NOTICE 'El fragmento % ya estaba en nodo_ushuaia', v_shard;
    END IF;
END
$$;


-- ---------------------------------------------------------
-- 4.2  Fragmento de Río Grande  ->  nodo_riogrande
-- ---------------------------------------------------------

DO $$
DECLARE
    v_shard  BIGINT;
    v_nodo   TEXT;
BEGIN
    v_shard := get_shard_id_for_distribution_column('titulaciones', 'Rio Grande');

    SELECT nodename INTO v_nodo
    FROM citus_shards
    WHERE shardid = v_shard
    LIMIT 1;

    IF v_nodo IS NULL THEN
        RAISE EXCEPTION 'No se encontró el fragmento de Río Grande.';
    END IF;

    IF v_nodo <> 'nodo_riogrande' THEN
        RAISE NOTICE 'Moviendo fragmento % de % a nodo_riogrande', v_shard, v_nodo;
        PERFORM citus_move_shard_placement(v_shard, v_nodo, 5432, 'nodo_riogrande', 5432);
    ELSE
        RAISE NOTICE 'El fragmento % ya estaba en nodo_riogrande', v_shard;
    END IF;
END
$$;


-- ---------------------------------------------------------
-- 4.3  ASERCIÓN: si la asignación falló, el despliegue aborta
-- ---------------------------------------------------------
-- Esto convierte al script en autoverificable: no se puede
-- terminar el despliegue con los datos en el nodo equivocado.
-- ---------------------------------------------------------

DO $$
DECLARE
    v_nodo_u TEXT;
    v_nodo_r TEXT;
BEGIN
    SELECT nodename INTO v_nodo_u FROM citus_shards
     WHERE shardid = get_shard_id_for_distribution_column('titulaciones', 'Ushuaia')
     LIMIT 1;

    SELECT nodename INTO v_nodo_r FROM citus_shards
     WHERE shardid = get_shard_id_for_distribution_column('titulaciones', 'Rio Grande')
     LIMIT 1;

    IF v_nodo_u <> 'nodo_ushuaia' THEN
        RAISE EXCEPTION 'FALLA: el fragmento de Ushuaia quedó en %', v_nodo_u;
    END IF;

    IF v_nodo_r <> 'nodo_riogrande' THEN
        RAISE EXCEPTION 'FALLA: el fragmento de Río Grande quedó en %', v_nodo_r;
    END IF;

    RAISE NOTICE '=== ASIGNACIÓN FÍSICA VERIFICADA: Ushuaia -> % / Río Grande -> % ===',
                 v_nodo_u, v_nodo_r;
END
$$;


-- =========================================================
-- 5. CLAVES FORÁNEAS HACIA LAS TABLAS DE REFERENCIA
-- =========================================================
-- Se agregan después de distribuir porque una FK desde una
-- tabla distribuida hacia una Reference Table solo puede
-- crearse cuando ambas ya tienen su tipo Citus asignado.
-- =========================================================

ALTER TABLE profesores_nomina
    ADD CONSTRAINT fk_nomina_clasif
    FOREIGN KEY (id_clasificaciones)
    REFERENCES clasificaciones(id_clasificaciones);

ALTER TABLE profesores_nomina
    ADD CONSTRAINT fk_nomina_pluses
    FOREIGN KEY (id_pluses_hijo)
    REFERENCES pluses_hijo(id_pluses_hijo);


-- =========================================================
-- 6. RESTRICCIÓN DE NEGOCIO: HORAS MÁXIMAS POR PROFESOR
-- =========================================================
-- Supuesto semántico: N_HORAS_MAX de CLASIFICACIONES debe
-- ser mayor o igual que la suma de NUM_HORAS de IMPARTE de
-- todos los registros del profesor.
--
-- No puede expresarse con un CHECK: un CHECK solo ve la fila
-- que se está insertando y esta regla necesita consultar
-- otras dos tablas (IMPARTE agregada y CLASIFICACIONES).
--
-- Se implementa como procedimiento almacenado, que actúa
-- como única vía de alta autorizada sobre IMPARTE.
-- Limitación asumida y documentada: un INSERT directo sobre
-- IMPARTE evita la validación. Por eso el guión de carga de
-- datos utiliza exclusivamente esta función.
-- =========================================================

CREATE OR REPLACE FUNCTION asignar_horas(
    p_id_profesor   INT,
    p_id_asignatura INT,
    p_id_curso      INT,
    p_id_titulacion INT,
    p_campus        VARCHAR,
    p_num_horas     INT
)
RETURNS VOID
AS $$
DECLARE
    v_max_horas      INT;
    v_horas_actuales INT;
    v_categoria      VARCHAR;
BEGIN

    IF p_num_horas <= 0 THEN
        RAISE EXCEPTION 'La cantidad de horas debe ser mayor que cero.';
    END IF;

    -- 1) Límite de horas según la categoría del profesor.
    --    La nómina está en Ushuaia; la consulta la resuelve
    --    el coordinador contra ese fragmento.
    SELECT c.num_horas_max, c.categoria
      INTO v_max_horas, v_categoria
      FROM profesores_nomina pn
      JOIN clasificaciones c
        ON pn.id_clasificaciones = c.id_clasificaciones
     WHERE pn.id_profesor = p_id_profesor;

    IF v_max_horas IS NULL THEN
        RAISE EXCEPTION
            'No existe información de nómina para el profesor %.', p_id_profesor;
    END IF;

    -- 2) Horas ya asignadas al profesor (en todas sus asignaturas).
    SELECT COALESCE(SUM(num_horas), 0)
      INTO v_horas_actuales
      FROM imparte
     WHERE id_profesor = p_id_profesor;

    -- 3) Validación de la regla.
    IF (v_horas_actuales + p_num_horas) > v_max_horas THEN
        RAISE EXCEPTION
            'El profesor % supera el límite de horas de su categoría "%". (Límite: %, Asignadas: %, Intento acumulado: %)',
            p_id_profesor,
            v_categoria,
            v_max_horas,
            v_horas_actuales,
            (v_horas_actuales + p_num_horas);
    END IF;

    -- 4) Alta autorizada.
    INSERT INTO imparte (
        id_profesor, id_asignatura, id_curso, id_titulacion, campus, num_horas
    )
    VALUES (
        p_id_profesor, p_id_asignatura, p_id_curso, p_id_titulacion, p_campus, p_num_horas
    );

END;
$$ LANGUAGE plpgsql;