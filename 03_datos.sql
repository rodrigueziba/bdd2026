-- =========================================================
-- CARGA DE DATOS DE PRUEBA Y DEMOSTRACIÓN
-- =========================================================

INSERT INTO pluses_hijo (descripcion, importe) VALUES 
('Bonus por Hijo', 15000.00),
('Bonus Guardería', 20000.00);

INSERT INTO clasificaciones (categoria, num_horas_max, max_salario) VALUES 
('Exclusivo', 40, 500000.00),
('Semi-Exclusivo', 20, 250000.00);

INSERT INTO titulaciones (id_titulacion, campus, nombre, creditos, nota_minima) VALUES 
(1, 'Ushuaia', 'Licenciatura en Sistemas', 240, 6.00),
(2, 'Rio Grande', 'Ingeniería Industrial', 280, 6.00);

INSERT INTO profesores (id_profesor, campus, nombre, direccion, telefono, email, despacho, id_clasificaciones, id_pluses_hijo) VALUES 
(101, 'Ushuaia', 'Ariel Parson', 'Calle Sol 123', '29014455', 'aparson@untdf.edu.ar', 'DESP001', 1, 1),
(201, 'Rio Grande', 'Nadia Ramos', 'Av. San Martin 456', '29641122', 'nramos@untdf.edu.ar', 'DESP002', 2, 2);