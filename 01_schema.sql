-- =========================================================
-- DISEÑO LÓGICO (ESQUEMA RELACIONAL)
-- =========================================================

-- 1. TABLAS DE CATÁLOGO / REFERENCIA
CREATE TABLE pluses_hijo (
    id_pluses_hijo SERIAL PRIMARY KEY,
    descripcion VARCHAR(150),
    importe NUMERIC(10,2) CHECK (importe >= 0)
);

CREATE TABLE clasificaciones (
    id_clasificaciones SERIAL PRIMARY KEY,
    categoria VARCHAR(50),
    num_horas_max INT,
    max_salario NUMERIC(10,2) CHECK (max_salario >= 0)
);

-- 2. TABLAS DE NEGOCIO (Incluyen 'campus' en la PK)
CREATE TABLE titulaciones (
    id_titulacion INT,
    campus VARCHAR(50),
    nombre VARCHAR(150),
    creditos INT,
    nota_minima NUMERIC(4,2),
    PRIMARY KEY (id_titulacion, campus)
);

CREATE TABLE cursos (
    id_curso INT,
    id_titulacion INT,
    campus VARCHAR(50),
    max_alumnos INT,
    PRIMARY KEY (id_curso, campus),
    FOREIGN KEY (id_titulacion, campus) REFERENCES titulaciones(id_titulacion, campus) ON DELETE CASCADE
);

CREATE TABLE grupos (
    id_grupo INT,
    id_curso INT,
    campus VARCHAR(50),
    turno VARCHAR(10) CHECK (turno IN ('MAÑANA', 'TARDE', 'NOCHE')),
    PRIMARY KEY (id_grupo, campus),
    FOREIGN KEY (id_curso, campus) REFERENCES cursos(id_curso, campus) ON DELETE CASCADE
);

CREATE TABLE asignaturas (
    id_asignatura INT,
    id_curso INT,
    campus VARCHAR(50),
    nombre_asig VARCHAR(150),
    horas_semanal INT,
    PRIMARY KEY (id_asignatura, campus),
    FOREIGN KEY (id_curso, campus) REFERENCES cursos(id_curso, campus) ON DELETE CASCADE
);

CREATE TABLE profesores (
    id_profesor INT,
    campus VARCHAR(50),
    nombre VARCHAR(100),
    direccion VARCHAR(150),
    telefono VARCHAR(8) CHECK ((telefono LIKE '2901%' OR telefono LIKE '2964%') AND length(telefono) = 8),
    email VARCHAR(100) CHECK (email LIKE '%@untdf.edu.ar'),
    despacho CHAR(7),
    id_clasificaciones INT,
    id_pluses_hijo INT,
    PRIMARY KEY (id_profesor, campus)
);

CREATE TABLE imparte (
    id_profesor INT,
    id_asignatura INT,
    campus VARCHAR(50),
    num_horas INT,
    PRIMARY KEY (id_profesor, id_asignatura, campus),
    FOREIGN KEY (id_profesor, campus) REFERENCES profesores(id_profesor, campus) ON DELETE CASCADE,
    FOREIGN KEY (id_asignatura, campus) REFERENCES asignaturas(id_asignatura, campus) ON DELETE CASCADE
);