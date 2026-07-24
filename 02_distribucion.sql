-- =========================================================
-- DISEÑO DISTRIBUIDO (CITUS) Y FOREIGN KEYS
-- =========================================================

-- 1. Replicación Total de Catálogos
SELECT create_reference_table('pluses_hijo');
SELECT create_reference_table('clasificaciones');

-- 2. Fragmentación Horizontal (Tablas Distribuidas)
SELECT create_distributed_table('titulaciones', 'campus');
SELECT create_distributed_table('cursos', 'campus');
SELECT create_distributed_table('grupos', 'campus');
SELECT create_distributed_table('asignaturas', 'campus');
SELECT create_distributed_table('profesores', 'campus');
SELECT create_distributed_table('imparte', 'campus');

-- 3. Reestablecer Foreign Keys (Ahora que Citus ya conoce la distribución)
ALTER TABLE profesores 
  ADD CONSTRAINT profesores_id_clasificaciones_fkey 
  FOREIGN KEY (id_clasificaciones) REFERENCES clasificaciones(id_clasificaciones);

ALTER TABLE profesores 
  ADD CONSTRAINT profesores_id_pluses_hijo_fkey 
  FOREIGN KEY (id_pluses_hijo) REFERENCES pluses_hijo(id_pluses_hijo);