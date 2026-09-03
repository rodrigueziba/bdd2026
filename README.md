# TP Integrador: Base de Datos Distribuida UNTDF

**Materia:** Bases de Datos Distribuidas  
**Alumno:** Ezequiel Ibarra  
**Institución:** Universidad Nacional de Tierra del Fuego, Antártida e Islas del Atlántico Sur (UNTDF)

Este repositorio contiene el código fuente, la infraestructura y los scripts de implementación para el Trabajo Práctico Integrador de diseño y despliegue de una base de datos distribuida homogénea utilizando **PostgreSQL** y la extensión **Citus**.

---

##  Guía de Ejecución

El proyecto está dockerizado y automatizado para que su despliegue sea transparente. 

### Prerrequisitos
* **Docker Desktop** instalado y en ejecución.
* **Git Bash** (o terminal compatible con scripts `.sh`).

### Pasos para levantar el entorno
1. **Clonar el repositorio e ingresar a la carpeta:**
   ```bash
   git clone https://github.com/rodrigueziba/bdd2026.git
   cd bdd2026

   docker compose down -v
   ./ejecutar_todo.sh