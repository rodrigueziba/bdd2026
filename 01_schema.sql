
CREATE TABLE pluses_hijo (
    id_pluses_hijo SERIAL PRIMARY KEY,
    descripcion VARCHAR(150),
    importe NUMERIC(10,2) CHECK (importe >= 0)
);

CREATE TABLE clasificaciones (
    id_clasificaciones SERIAL PRIMARY KEY,
    categoria VARCHAR(50) NOT NULL,
    num_horas_max INT NOT NULL
        CHECK (num_horas_max > 0),
    max_salario NUMERIC(10,2) NOT NULL
        CHECK (max_salario >= 0)
);


CREATE TABLE titulaciones (
    id_titulacion INT NOT NULL,
    campus VARCHAR(50) NOT NULL,
    nombre VARCHAR(150) NOT NULL,
    creditos INT NOT NULL
        CHECK (creditos > 0),
    nota_minima NUMERIC(4,2) NOT NULL
        CHECK (nota_minima >= 0 AND nota_minima <= 10),

    PRIMARY KEY (id_titulacion, campus)
);

CREATE TABLE cursos (
    id_curso INT NOT NULL,
    id_titulacion INT NOT NULL,
    campus VARCHAR(50) NOT NULL,
    max_alumnos INT NOT NULL
        CHECK (max_alumnos > 0),

    PRIMARY KEY (id_curso, id_titulacion, campus),

    FOREIGN KEY (id_titulacion, campus)
        REFERENCES titulaciones(id_titulacion, campus)
        ON DELETE CASCADE
);

CREATE TABLE grupos (
    id_grupo INT NOT NULL,
    id_curso INT NOT NULL,
    id_titulacion INT NOT NULL,
    campus VARCHAR(50) NOT NULL,
    turno VARCHAR(10) NOT NULL
        CHECK (turno IN ('MAÑANA', 'TARDE', 'NOCHE')),

    PRIMARY KEY (id_grupo, id_curso, id_titulacion, campus),

    FOREIGN KEY (id_curso, id_titulacion, campus)
        REFERENCES cursos(id_curso, id_titulacion, campus)
        ON DELETE CASCADE
);

CREATE TABLE asignaturas (
    id_asignatura INT NOT NULL,
    id_curso INT NOT NULL,
    id_titulacion INT NOT NULL,
    campus VARCHAR(50) NOT NULL,
    nombre_asig VARCHAR(150) NOT NULL,
    horas_semanal INT NOT NULL
        CHECK (horas_semanal > 0),

    PRIMARY KEY (
        id_asignatura,
        id_curso,
        id_titulacion,
        campus
    ),

    FOREIGN KEY (
        id_curso,
        id_titulacion,
        campus
    )
        REFERENCES cursos(
            id_curso,
            id_titulacion,
            campus
        )
        ON DELETE CASCADE
);

-- =========================================================
-- PROFESORES
-- Fragmentación híbrida:
--   - datos de contacto por campus
--   - datos de nómina en Ushuaia
-- =========================================================

CREATE TABLE profesores (
    id_profesor INT NOT NULL,
    campus VARCHAR(50) NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    direccion VARCHAR(150) NOT NULL,

    telefono VARCHAR(8) NOT NULL
        CHECK (
            length(telefono) = 8
            AND telefono ~ '^[0-9]+$'
            AND (
                (
                    campus = 'Ushuaia'
                    AND telefono LIKE '2901%'
                )
                OR
                (
                    campus = 'Rio Grande'
                    AND telefono LIKE '2964%'
                )
            )
        ),

 email VARCHAR(100) NOT NULL
    CHECK (email ~ '^[A-Za-z0-9._%+-]+@untdf\.edu\.ar$'),

    despacho CHAR(7) NOT NULL
        CHECK (length(trim(despacho)) = 7),

    PRIMARY KEY (id_profesor, campus),

    -- La restricción incluye campus porque la tabla
    -- se distribuye por campus y Citus exige que una
    -- restricción UNIQUE sobre una tabla distribuida
    -- incluya la columna de distribución.
    UNIQUE (email, campus)
);

-- =========================================================
-- PROFESORES_NOMINA
-- Fragmento vertical almacenado en sede central Ushuaia
-- =========================================================

CREATE TABLE profesores_nomina (
    id_profesor INT NOT NULL,
    sede_nomina VARCHAR(50) NOT NULL DEFAULT 'Ushuaia'
        CHECK (sede_nomina = 'Ushuaia'),

    id_clasificaciones INT NOT NULL,
    id_pluses_hijo INT NOT NULL,

    PRIMARY KEY (id_profesor, sede_nomina)
);

-- =========================================================
-- IMPARTE
-- Relación N:M entre PROFESORES y ASIGNATURAS
-- =========================================================

CREATE TABLE imparte (
    id_profesor INT NOT NULL,
    id_asignatura INT NOT NULL,
    id_curso INT NOT NULL,
    id_titulacion INT NOT NULL,
    campus VARCHAR(50) NOT NULL,
    num_horas INT NOT NULL
        CHECK (num_horas > 0),

    PRIMARY KEY (
        id_profesor,
        id_asignatura,
        id_curso,
        id_titulacion,
        campus
    ),

    FOREIGN KEY (
        id_profesor,
        campus
    )
        REFERENCES profesores(
            id_profesor,
            campus
        )
        ON DELETE CASCADE,

    FOREIGN KEY (
        id_asignatura,
        id_curso,
        id_titulacion,
        campus
    )
        REFERENCES asignaturas(
            id_asignatura,
            id_curso,
            id_titulacion,
            campus
        )
        ON DELETE CASCADE
);

-- =========================================================
-- ÍNDICES
-- =========================================================

CREATE INDEX idx_cursos_titulacion
    ON cursos(id_titulacion, campus);

CREATE INDEX idx_grupos_curso
    ON grupos(id_curso, id_titulacion, campus);

CREATE INDEX idx_asignaturas_curso
    ON asignaturas(id_curso, id_titulacion, campus);

CREATE INDEX idx_profesores_email
    ON profesores(email);

CREATE INDEX idx_imparte_profesor
    ON imparte(id_profesor, campus);

CREATE INDEX idx_imparte_asignatura
    ON imparte(
        id_asignatura,
        id_curso,
        id_titulacion,
        campus
    );