-- =========================================================
-- BASES DE DATOS DISTRIBUIDAS - UNTDF
-- 03 - CARGA DE DATOS INICIALES
-- =========================================================
-- Los volúmenes por sede son deliberadamente DISTINTOS
-- (Ushuaia carga más filas que Río Grande en casi todas las
-- tablas). Esto permite demostrar la ubicación física de los
-- datos: si cada nodo devuelve un número diferente y ese
-- número coincide con el de su sede, la fragmentación es
-- real y no una coincidencia.
--
--   TABLA                Ushuaia   Río Grande
--   titulaciones            2          1
--   cursos                  3          1
--   grupos                  4          1
--   asignaturas             4          3
--   profesores              3          2
--   imparte                 4          2
--   profesores_nomina       5          0
-- =========================================================


-- =========================================================
-- 1. CATÁLOGOS REPLICADOS
-- =========================================================

INSERT INTO pluses_hijo (id_pluses_hijo, descripcion, importe) VALUES
    (1, 'Asignación por Hijo',       15000.00),
    (2, 'Subsidio Guardería',        20000.00),
    (3, 'Sin plus asignado',             0.00);

INSERT INTO clasificaciones (id_clasificaciones, categoria, num_horas_max, max_salario) VALUES
    (1, 'Titular Exclusivo',        40, 500000.00),
    (2, 'Adjunto Simple',           10, 150000.00),
    (3, 'Asociado Semiexclusivo',   20, 300000.00);


-- =========================================================
-- 2. TITULACIONES
-- =========================================================

INSERT INTO titulaciones (id_titulacion, campus, nombre, creditos, nota_minima) VALUES
    (1, 'Ushuaia',    'Licenciatura en Sistemas',   240, 6.00),
    (2, 'Rio Grande', 'Ingeniería Industrial',      280, 6.00),
    (3, 'Ushuaia',    'Licenciatura en Turismo',    220, 6.00);


-- =========================================================
-- 3. CURSOS  (entidad débil)
-- =========================================================
-- Obsérvese el caso clave: el "curso 1" existe en la
-- titulación 1 Y en la titulación 3, ambas del MISMO campus.
-- Eso solo es posible porque id_titulacion forma parte de la
-- clave primaria de CURSOS. Con una PK simple sobre id_curso
-- la segunda fila sería rechazada.
-- =========================================================

INSERT INTO cursos (id_curso, id_titulacion, campus, max_alumnos) VALUES
    (1, 1, 'Ushuaia',    40),
    (2, 1, 'Ushuaia',    35),
    (1, 3, 'Ushuaia',    30),   -- mismo id_curso, misma sede, otra titulación
    (1, 2, 'Rio Grande', 35);


-- =========================================================
-- 4. GRUPOS
-- =========================================================

INSERT INTO grupos (id_grupo, id_curso, id_titulacion, campus, turno) VALUES
    (1, 1, 1, 'Ushuaia',    'TARDE'),
    (2, 1, 1, 'Ushuaia',    'NOCHE'),
    (1, 2, 1, 'Ushuaia',    'MAÑANA'),
    (1, 1, 3, 'Ushuaia',    'TARDE'),
    (1, 1, 2, 'Rio Grande', 'NOCHE');


-- =========================================================
-- 5. ASIGNATURAS
-- =========================================================

INSERT INTO asignaturas (id_asignatura, id_curso, id_titulacion, campus, nombre_asig, horas_semanal) VALUES
    (1, 1, 1, 'Ushuaia',    'Bases de Datos Distribuidas', 6),
    (2, 1, 1, 'Ushuaia',    'Redes de Computadoras',       4),
    (3, 2, 1, 'Ushuaia',    'Sistemas Operativos',         5),
    (4, 1, 3, 'Ushuaia',    'Geografía Turística',         8),
    (5, 1, 2, 'Rio Grande', 'Física II',                   8),
    (6, 1, 2, 'Rio Grande', 'Cálculo',                     4),
    (7, 1, 2, 'Rio Grande', 'Química General',             4);


-- =========================================================
-- 6. PROFESORES  (fragmento de contacto, por campus)
-- =========================================================
-- Teléfonos: 2901 en Ushuaia, 2964 en Río Grande.
-- Correos: inicial + apellido @untdf.edu.ar
-- =========================================================

INSERT INTO profesores (id_profesor, campus, nombre, direccion, telefono, email, despacho) VALUES
    (101, 'Ushuaia',    'Ariel Parson', 'Yaganes 123',   '29014455', 'aparson@untdf.edu.ar', 'DESP001'),
    (102, 'Ushuaia',    'Laura Gomez',  'Kuanip 456',    '29017788', 'lgomez@untdf.edu.ar',  'DESP002'),
    (103, 'Ushuaia',    'Pablo Diaz',   'Onas 789',      '29013322', 'pdiaz@untdf.edu.ar',   'DESP003'),
    (201, 'Rio Grande', 'Nadia Ramos',  'Thorne 456',    '29641122', 'nramos@untdf.edu.ar',  'DESP101'),
    (202, 'Rio Grande', 'Marta Silva',  'Piedrabuena 12','29645566', 'msilva@untdf.edu.ar',  'DESP102');


-- =========================================================
-- 7. PROFESORES_NOMINA  (fragmento vertical, todo en Ushuaia)
-- =========================================================
-- Aquí se ve el punto central de la fragmentación híbrida:
-- los docentes 201 y 202 trabajan en Río Grande, pero su
-- información de nómina se almacena en Ushuaia, porque el
-- departamento de nóminas y contrataciones se mantiene allí.
-- =========================================================

INSERT INTO profesores_nomina (id_profesor, sede_nomina, id_clasificaciones, id_pluses_hijo) VALUES
    (101, 'Ushuaia', 1, 1),   -- Titular Exclusivo      -> 40 h
    (102, 'Ushuaia', 2, 3),   -- Adjunto Simple         -> 10 h
    (103, 'Ushuaia', 3, 2),   -- Asociado Semiexclusivo -> 20 h
    (201, 'Ushuaia', 2, 1),   -- Adjunto Simple         -> 10 h
    (202, 'Ushuaia', 1, 3);   -- Titular Exclusivo      -> 40 h


-- =========================================================
-- 8. IMPARTE  (cargado a través del procedimiento almacenado)
-- =========================================================
-- No se usan INSERT directos a propósito: todas las altas
-- pasan por asignar_horas(), que valida la restricción de
-- horas máximas. Que este guión termine sin error es, en sí
-- mismo, una prueba de que la restricción está activa y de
-- que ninguna asignación viola el límite de su categoría.
-- =========================================================

SELECT asignar_horas(101, 1, 1, 1, 'Ushuaia',    6);  -- 6/40
SELECT asignar_horas(101, 2, 1, 1, 'Ushuaia',    4);  -- 10/40
SELECT asignar_horas(102, 3, 2, 1, 'Ushuaia',    5);  -- 5/10
SELECT asignar_horas(103, 4, 1, 3, 'Ushuaia',    8);  -- 8/20
SELECT asignar_horas(201, 5, 1, 2, 'Rio Grande', 8);  -- 8/10
SELECT asignar_horas(202, 6, 1, 2, 'Rio Grande', 4);  -- 4/40