
-- 1. Catálogos (Replicados)
INSERT INTO pluses_hijo (id_pluses_hijo, descripcion, importe) VALUES 
(1, 'Asignación por Hijo', 15000.00),
(2, 'Subsidio Guardería', 20000.00);

INSERT INTO clasificaciones (id_clasificaciones, categoria, num_horas_max, max_salario) VALUES 
(1, 'Titular Exclusivo', 40, 500000.00),
(2, 'Adjunto Simple', 10, 150000.00);

-- 2. Titulaciones
INSERT INTO titulaciones (id_titulacion, campus, nombre, creditos, nota_minima) VALUES 
(1, 'Ushuaia', 'Licenciatura en Sistemas', 240, 6.00),
(2, 'Rio Grande', 'Ingeniería Industrial', 280, 6.00);

-- 3. Cursos (Entidad Débil: Depende de Titulación)
-- Observación: Ambas carreras tienen un "Curso 1", demostrando que la entidad débil funciona
INSERT INTO cursos (id_curso, id_titulacion, campus, max_alumnos) VALUES 
(1, 1, 'Ushuaia', 40),
(1, 2, 'Rio Grande', 35); 

-- 4. Grupos 
INSERT INTO grupos (id_grupo, id_curso, id_titulacion, campus, turno) VALUES 
(1, 1, 1, 'Ushuaia', 'TARDE'),
(1, 1, 2, 'Rio Grande', 'NOCHE');

-- 5. Asignaturas
INSERT INTO asignaturas (id_asignatura, id_curso, id_titulacion, campus, nombre_asig, horas_semanal) VALUES 
(1, 1, 1, 'Ushuaia', 'Bases de Datos Distribuidas', 6),
(2, 1, 2, 'Rio Grande', 'Física II', 8);

-- 6. Profesores (Fragmentación Vertical: Solo datos de contacto distribuidos por campus)
INSERT INTO profesores (id_profesor, campus, nombre, direccion, telefono, email, despacho) VALUES 
(101, 'Ushuaia', 'Ariel Parson', 'Yaganes 123', '29014455', 'aparson@untdf.edu.ar', 'DESP001'),
(201, 'Rio Grande', 'Nadia Ramos', 'Thorne 456', '29641122', 'nramos@untdf.edu.ar', 'DESP002');

-- 7. Profesores Nómina (Fragmentación Vertical: Todos los registros van a Ushuaia)
INSERT INTO profesores_nomina (id_profesor, sede_nomina, id_clasificaciones, id_pluses_hijo) VALUES 
(101, 'Ushuaia', 1, 1),
(201, 'Ushuaia', 2, 2);

-- 8. Imparte (Relación entre Profesores y Asignaturas)
INSERT INTO imparte (id_profesor, id_asignatura, id_curso, id_titulacion, campus, num_horas) VALUES 
(101, 1, 1, 1, 'Ushuaia', 6),
(201, 2, 1, 2, 'Rio Grande', 8);