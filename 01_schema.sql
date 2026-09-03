-- =========================================================
-- BASES DE DATOS DISTRIBUIDAS - UNTDF
-- 01 - ESQUEMA LÓGICO, RESTRICCIONES E ÍNDICES
-- =========================================================
-- Este script crea las tablas como tablas Postgres normales.
-- Todavía no hay nada distribuido: eso ocurre en 02.
-- =========================================================


-- =========================================================
-- CATÁLOGOS (serán tablas de referencia / replicación total)
-- =========================================================
-- Se usa INT y no SERIAL porque los identificadores de los
-- catálogos se cargan de forma controlada desde el guión DML.
-- Con SERIAL, insertar el id explícitamente deja la secuencia
-- desfasada y el siguiente INSERT sin id chocaría con la PK.
-- =========================================================

CREATE TABLE pluses_hijo (
    id_pluses_hijo INT NOT NULL,
    descripcion VARCHAR(150) NOT NULL,
    importe NUMERIC(10,2) NOT NULL
        CHECK (importe >= 0),

    PRIMARY KEY (id_pluses_hijo)
);

CREATE TABLE clasificaciones (
    id_clasificaciones INT NOT NULL,
    categoria VARCHAR(50) NOT NULL,
    num_horas_max INT NOT NULL
        CHECK (num_horas_max > 0),
    max_salario NUMERIC(10,2) NOT NULL
        CHECK (max_salario >= 0),

    PRIMARY KEY (id_clasificaciones)
);


-- =========================================================
-- TITULACIONES
-- Fragmentación horizontal primaria por CAMPUS.
-- campus forma parte de la PK porque es la clave de
-- distribución y Citus exige que la PK de una tabla
-- distribuida la contenga.
-- =========================================================

CREATE TABLE titulaciones (
    id_titulacion INT NOT NULL,
    campus VARCHAR(50) NOT NULL
        CHECK (campus IN ('Ushuaia', 'Rio Grande')),
    nombre VARCHAR(150) NOT NULL,
    creditos INT NOT NULL
        CHECK (creditos > 0),
    nota_minima NUMERIC(4,2) NOT NULL
        CHECK (nota_minima >= 0 AND nota_minima <= 10),

    PRIMARY KEY (id_titulacion, campus)
);


-- =========================================================
-- CURSOS  (ENTIDAD DÉBIL de TITULACIONES)
-- La PK incluye id_titulacion: por eso dos titulaciones
-- distintas SÍ pueden tener un curso con el mismo número.
-- =========================================================

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


-- =========================================================
-- GRUPOS
-- Fragmentación horizontal derivada de CURSOS.
-- =========================================================

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


-- =========================================================
-- ASIGNATURAS
-- Fragmentación horizontal derivada de CURSOS.
-- =========================================================

CREATE TABLE asignaturas (
    id_asignatura INT NOT NULL,
    id_curso INT NOT NULL,
    id_titulacion INT NOT NULL,
    campus VARCHAR(50) NOT NULL,
    nombre_asig VARCHAR(150) NOT NULL,
    horas_semanal INT NOT NULL
        CHECK (horas_semanal > 0),

    PRIMARY KEY (id_asignatura, id_curso, id_titulacion, campus),

    FOREIGN KEY (id_curso, id_titulacion, campus)
        REFERENCES cursos(id_curso, id_titulacion, campus)
        ON DELETE CASCADE
);


-- =========================================================
-- PROFESORES  -- FRAGMENTO DE CONTACTO
-- Primera mitad de la fragmentación híbrida.
-- Se fragmenta horizontalmente por campus: cada departamento
-- gestiona los datos de contacto de sus propios docentes.
-- =========================================================

CREATE TABLE profesores (
    id_profesor INT NOT NULL,
    campus VARCHAR(50) NOT NULL
        CHECK (campus IN ('Ushuaia', 'Rio Grande')),
    nombre VARCHAR(100) NOT NULL,
    direccion VARCHAR(150) NOT NULL,

    -- Supuesto semántico: entero de longitud fija 8 que
    -- comienza en 2901 (Ushuaia) o 2964 (Río Grande).
    telefono VARCHAR(8) NOT NULL
        CHECK (
            telefono ~ '^[0-9]{8}$'
            AND (
                (campus = 'Ushuaia'    AND telefono LIKE '2901%')
                OR
                (campus = 'Rio Grande' AND telefono LIKE '2964%')
            )
        ),

    -- Supuesto semántico: formato inicial + apellido @untdf.edu.ar
    email VARCHAR(100) NOT NULL
        CHECK (email ~ '^[a-z][a-z]+@untdf\.edu\.ar$'),

    -- Supuesto semántico: longitud fija de 7 caracteres.
    despacho CHAR(7) NOT NULL
        CHECK (length(trim(despacho)) = 7),

    PRIMARY KEY (id_profesor, campus),

    -- Clave alternativa sobre el correo electrónico.
    -- Incluye campus porque Citus exige que toda restricción
    -- UNIQUE sobre una tabla distribuida contenga la columna
    -- de distribución (el índice único vive dentro de cada
    -- fragmento, no puede ser global al clúster).
    -- Alcance real: unicidad garantizada dentro de cada sede.
    UNIQUE (email, campus)
);


-- =========================================================
-- PROFESORES_NOMINA  -- FRAGMENTO SALARIAL
-- Segunda mitad de la fragmentación híbrida.
-- Fragmento VERTICAL: se separan los atributos de nómina y
-- se alojan íntegramente en la sede central de Ushuaia,
-- como exige el requerimiento.
--
-- El CHECK sobre sede_nomina garantiza a nivel de dominio
-- que ninguna fila de nómina pueda pertenecer a otra sede.
--
-- LIMITACIÓN CONOCIDA: no puede declararse una FOREIGN KEY
-- hacia PROFESORES. Citus solo admite claves foráneas entre
-- tablas distribuidas si ambas comparten columna de
-- distribución y grupo de co-localización. Las
-- columnas son distintas a propósito (campus vs sede_nomina).
-- La integridad se sostiene por diseño (sede_nomina fija) y
-- a nivel de aplicación.
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
-- Interrelación N:M entre PROFESORES y ASIGNATURAS.
-- Fragmentación horizontal derivada por campus.
-- =========================================================

CREATE TABLE imparte (
    id_profesor INT NOT NULL,
    id_asignatura INT NOT NULL,
    id_curso INT NOT NULL,
    id_titulacion INT NOT NULL,
    campus VARCHAR(50) NOT NULL,
    num_horas INT NOT NULL
        CHECK (num_horas > 0),

    PRIMARY KEY (id_profesor, id_asignatura, id_curso, id_titulacion, campus),

    FOREIGN KEY (id_profesor, campus)
        REFERENCES profesores(id_profesor, campus)
        ON DELETE CASCADE,

    FOREIGN KEY (id_asignatura, id_curso, id_titulacion, campus)
        REFERENCES asignaturas(id_asignatura, id_curso, id_titulacion, campus)
        ON DELETE CASCADE
);


-- =========================================================
-- ÍNDICES  (tareas de optimización del diseño físico)
-- =========================================================
-- Las PK ya generan índices. Estos cubren los accesos que
-- NO son por prefijo de la PK
-- =========================================================

CREATE INDEX idx_cursos_titulacion
    ON cursos (id_titulacion, campus);

CREATE INDEX idx_grupos_curso
    ON grupos (id_curso, id_titulacion, campus);

CREATE INDEX idx_asignaturas_curso
    ON asignaturas (id_curso, id_titulacion, campus);

CREATE INDEX idx_profesores_email
    ON profesores (email);

CREATE INDEX idx_imparte_profesor
    ON imparte (id_profesor, campus);

CREATE INDEX idx_imparte_asignatura
    ON imparte (id_asignatura, id_curso, id_titulacion, campus);

CREATE INDEX idx_nomina_clasificacion
    ON profesores_nomina (id_clasificaciones);