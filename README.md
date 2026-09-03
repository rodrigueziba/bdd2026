# TP Integrador: Base de Datos Distribuida UNTDF

**Materia:** Bases de Datos Distribuidas
**Alumno:** Ezequiel Rodriguez Ibarra
**Institución:** Universidad Nacional de Tierra del Fuego, Antártida e Islas del Atlántico Sur

Implementación de una base de datos distribuida homogénea sobre PostgreSQL 16
con la extensión Citus 12.1, desplegada en tres contenedores Docker que simulan
el nodo coordinador y los servidores de las sedes Ushuaia y Río Grande.

---

## Prerrequisitos

- Docker Desktop instalado y en ejecución
- Git Bash o cualquier terminal compatible con scripts `.sh`

## Despliegue

```bash
git clone https://github.com/rodrigueziba/bdd2026.git
cd bdd2026

chmod +x ejecutar_todo.sh 05_pruebas_nodos.sh

docker compose down -v
./ejecutar_todo.sh
```

El despliegue se autoverifica: si los fragmentos de cada sede no quedan
alojados en el nodo correspondiente, el script aborta con una excepción.

## Pruebas

```bash
# Once pruebas desde el nodo coordinador
docker exec -i nodo_coordinador psql -U ezequiel -d untdf_db < 04_pruebas.sql

# Siete pruebas ejecutadas dentro de cada servidor de campus
./05_pruebas_nodos.sh
```

Las pruebas 8.b, 9 y 10 producen un error de la base de datos **de forma
deliberada**: ese error es el resultado esperado y demuestra que la
restricción correspondiente está activa.

## Conexión

| Nodo | Host | Puerto |
|---|---|---|
| Coordinador | localhost | 5532 |
| Sede Ushuaia | localhost | 5533 |
| Sede Río Grande | localhost | 5534 |

Base de datos `untdf_db`, usuario `ezequiel`, contraseña `admin`.

Por consola:

```bash
docker exec -it nodo_coordinador psql -U ezequiel -d untdf_db
docker exec -it nodo_ushuaia     psql -U ezequiel -d untdf_db
docker exec -it nodo_riogrande   psql -U ezequiel -d untdf_db
```

Para salir de la consola interactiva: `\q`

## Detener y reanudar

```bash
docker compose stop     # detiene conservando los datos
docker compose start    # reanuda
docker compose down -v  # elimina contenedores y datos
```

## Estructura del entregable

| Archivo | Contenido |
|---|---|
| `docker-compose.yml` | Orquestación del clúster de tres nodos |
| `01_schema.sql` | DDL: esquema lógico, restricciones e índices |
| `02_distribucion.sql` | Replicación, fragmentación, asignación física y procedimiento de validación |
| `03_datos.sql` | DML: carga de datos iniciales |
| `04_pruebas.sql` | Pruebas de validación desde el coordinador |
| `05_pruebas_nodos.sh` | Pruebas ejecutadas dentro de cada servidor de campus |
| `ejecutar_todo.sh` | Despliegue automatizado completo |

## Distribución de los datos

| Tabla | Tipo en Citus | Ushuaia | Río Grande |
|---|---|---|---|
| `pluses_hijo` | Reference (replicada) | 3 | 3 |
| `clasificaciones` | Reference (replicada) | 3 | 3 |
| `titulaciones` | Distribuida por `campus` | 2 | 1 |
| `cursos` | Distribuida por `campus` | 3 | 1 |
| `grupos` | Distribuida por `campus` | 4 | 1 |
| `asignaturas` | Distribuida por `campus` | 4 | 3 |
| `profesores` | Distribuida por `campus` | 3 | 2 |
| `imparte` | Distribuida por `campus` | 4 | 2 |
| `profesores_nomina` | Distribuida por `sede_nomina` | 5 | 0 |

Los volúmenes son deliberadamente asimétricos: permiten demostrar que la
ubicación física de los datos es la esperada y no producto del azar.
