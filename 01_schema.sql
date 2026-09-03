
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
    
   
    PRIMARY KEY (id_curso, id_titulacion, campus),
    FOREIGN KEY (id_titulacion, campus) REFERENCES titulaciones(id_titulacion, campus) ON DELETE CASCADE
);

CREATE TABLE grupos (
    id_grupo INT,
    id_curso INT,
    id_titulacion INT, 
    campus VARCHAR(50),
    turno VARCHAR(10) CHECK (turno IN ('MAÑANA', 'TARDE', 'NOCHE')),
    
    PRIMARY KEY (id_grupo, id_curso, id_titulacion, campus),
    FOREIGN KEY (id_curso, id_titulacion, campus) REFERENCES cursos(id_curso, id_titulacion, campus) ON DELETE CASCADE
);

CREATE TABLE asignaturas (
    id_asignatura INT,
    id_curso INT,
    id_titulacion INT, 
    campus VARCHAR(50),
    nombre_asig VARCHAR(150),
    horas_semanal INT,
    
    PRIMARY KEY (id_asignatura, id_curso, id_titulacion, campus),
    FOREIGN KEY (id_curso, id_titulacion, campus) REFERENCES cursos(id_curso, id_titulacion, campus) ON DELETE CASCADE
);


CREATE TABLE profesores (
    id_profesor INT,
    campus VARCHAR(50),
    nombre VARCHAR(100),
    direccion VARCHAR(150),
    telefono VARCHAR(8) CHECK (
        length(telefono) = 8 AND 
        telefono ~ '^[0-9]+$' AND (
            (campus = 'Ushuaia' AND telefono LIKE '2901%') OR 
            (campus = 'Rio Grande' AND telefono LIKE '2964%')
        )
    ),
   email VARCHAR(100) CHECK (email LIKE '%@untdf.edu.ar'),
   despacho CHAR(7) CHECK (length(trim(despacho)) = 7),
    PRIMARY KEY (id_profesor, campus),
    UNIQUE (email, campus)
);


CREATE TABLE profesores_nomina (
    id_profesor INT,
    sede_nomina VARCHAR(50) DEFAULT 'Ushuaia', 
    id_clasificaciones INT,
    id_pluses_hijo INT,
    PRIMARY KEY (id_profesor, sede_nomina)
);


CREATE TABLE imparte (
    id_profesor INT,
    id_asignatura INT,
    id_curso INT,      
    id_titulacion INT,  
    campus VARCHAR(50),
    num_horas INT,
    
    PRIMARY KEY (id_profesor, id_asignatura, id_curso, id_titulacion, campus),
    FOREIGN KEY (id_profesor, campus) REFERENCES profesores(id_profesor, campus) ON DELETE CASCADE,
    FOREIGN KEY (id_asignatura, id_curso, id_titulacion, campus) REFERENCES asignaturas(id_asignatura, id_curso, id_titulacion, campus) ON DELETE CASCADE
);

CREATE INDEX idx_cursos_titulacion ON cursos(id_titulacion, campus);
CREATE INDEX idx_grupos_curso ON grupos(id_curso, id_titulacion, campus);
CREATE INDEX idx_asignaturas_curso ON asignaturas(id_curso, id_titulacion, campus);
CREATE INDEX idx_profesores_email ON profesores(email);
CREATE INDEX idx_imparte_profesor ON imparte(id_profesor, campus);
CREATE INDEX idx_imparte_asignatura ON imparte(id_asignatura, id_curso, id_titulacion, campus);

