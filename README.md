# 🏭 FICSIT Production Optimizer // Satisfactory 1.0 Factory Planner

Una aplicación web de alto rendimiento escrita en el lenguaje de programación **Nim**, que compila directamente a **JavaScript** para ejecutarse en el navegador. Diseñada con la estética corporativa de **FICSIT Inc.** de *Satisfactory 1.0*, permite planificar cadenas de producción industriales complejas, optimizar ratios de máquinas y resolver matemáticamente la gestión de recursos, subproductos (byproducts) y reciclaje en bucle cerrado.

---

## ⚡ Características Principales

1. **Resolutor de Programación Lineal (Algoritmo Simplex Dual en Nim Puro)**:
   - Modela toda la fábrica como un problema de optimización lineal ($A x \ge b$).
   - Minimiza de forma óptima el consumo de materias primas naturales y la cantidad total de edificios.
   - **Gestión Matemática de Subproductos y Bucles**: Resuelve automáticamente situaciones complejas como el reciclaje de agua en *Aluminum Scrap* / *Alumina Solution*, el aprovechamiento de *Heavy Oil Residue* y *Polymer Resin* en refinerías de petróleo, o subproductos de combustibles nucleares y *Rocket Fuel*.
   - Reutiliza automáticamente los subproductos internamente antes de solicitar recursos frescos de la naturaleza.

2. **Base de Datos Oficial Completa Satisfactory 1.0**:
   - Más de **211 ítems** y **296 recetas** extraídas de la versión 1.0 de Satisfactory (incluyendo fase 5 del *Space Elevator*, codificadores cuánticos, convertidores y fragmentos de energía sintéticos).
   - Incluye catálogo de más de **110 recetas alternativas** (*Alternate Recipes*) descubiertas en discos duros (*Hard Drives*).

3. **Diagrama de Flujo Interactivo (DAG en SVG)**:
   - Representación visual del flujo dirigido de materiales por etapas: Extracción ➔ Nivel 1 ➔ Ensamblajes Intermedios ➔ Productos Finales.
   - Muestra tasas de transporte exactas (ítems/min) sobre cada conexión.

4. **Presets de Fábrica Listos para Usar**:
   - 🚀 **Space Elevator Fases 1 a 5** (desde *Smart Plating* hasta *Ballistic Warp Drive* y *AI Expansion Server*).
   - 🏗️ **Heavy Modular Frame Mega-Factory** (10/min).
   - 💧 **Aluminum & Battery Complex con reciclaje de agua en bucle**.
   - 💻 **Centro de Supercomputadoras** y RCU.
   - ⛽ **Refinería de Rocket Fuel y Plástico**.

5. **Recomendación de Clock Speeds y Mineros**:
   - Desglose detallado de cuántas máquinas se necesitan a 100% de reloj y qué porcentaje asignar a la última máquina para evitar cuellos de botella (o reloj uniforme).
   - Cálculo del consumo total de energía eléctrica en **MW**.
   - Sugerencias de mineros (*Miner Mk.1 / Mk.2 / Mk.3*, extractores de agua, extractores de petróleo).

---

## 🚀 Instrucciones de Ejecución en WSL

Dado que estamos en **WSL (Windows Subsystem for Linux)**, el servidor web local se enlaza a `0.0.0.0:8080`, lo que permite acceder directamente desde cualquier navegador instalado en Windows (Chrome, Edge, Firefox, Brave) a través de `localhost`.

### 1. Iniciar el Servidor Web

Ejecuta el script proporcionado:

```bash
./scripts/serve.sh
```

Verás una salida como:
```
================================================================
🏭 FICSIT PRODUCTION OPTIMIZER (SATISFACTORY 1.0)
   Servidor web local para WSL y navegador de Windows
================================================================

🚀 Servidor iniciado en puerto 8080.
👉 Abre en tu navegador (Windows o Linux):
   http://localhost:8080
   http://127.0.0.1:8080
```

Abre tu navegador habitual en Windows y entra a:
👉 **[http://localhost:8080](http://localhost:8080)**

---

## 🛠️ Compilación con Nim

Si realizas cambios en el código fuente de Nim, puedes recompilar la aplicación a JavaScript con un solo comando:

```bash
./scripts/build.sh
```

Esto ejecuta el compilador Nim con la flag de optimización de lanzamiento (`-d:release`):
```bash
./.nim_toolchain/bin/nim js --path:src -d:release -o:web/app.js src/main.nim
```

El resultado es un único archivo JavaScript standalone (`web/app.js`) que contiene:
- El motor matemático Simplex.
- La base de datos completa de Satisfactory 1.0 embebida en tiempo de compilación.
- El generador de SVG y el sistema reactivo del DOM.

---

## 📁 Estructura del Proyecto

```
satisfactory_planner/
├── .nim_toolchain/            # Compilador Nim (v2.4.0) y librerías estándar
├── data/
│   └── raw_data.json          # Dataset completo Satisfactory 1.0 (recetas, ítems, máquinas)
├── src/
│   ├── types.nim              # Modelos de datos (Item, Recipe, FactoryTarget, FactoryPlan, etc.)
│   ├── dataset.nim            # Carga e indexación en memoria de la base de datos del juego
│   ├── simplex.nim            # Motor de Programación Lineal (Simplex Dual) en Nim
│   ├── planner.nim            # Generador del plan de fábrica, análisis de subproductos y DAG
│   ├── presets.nim            # Presets preconfigurados para fases del Space Elevator y fábricas
│   ├── svg_graph.nim          # Generador de gráficos de flujo vectoriales (SVG)
│   ├── ui.nim                 # Interfaz de usuario interactiva y componentes DOM
│   └── main.nim               # Punto de entrada de la aplicación
├── web/
│   ├── index.html             # Página web principal
│   ├── style.css              # Estilos FICSIT oscuros con detalles en naranja (#FA9549)
│   └── app.js                 # Código JavaScript compilado por Nim
├── scripts/
│   ├── build.sh               # Script de compilación rápida
│   └── serve.sh               # Servidor local compatible con WSL
└── README.md                  # Este documento
```

---

## 🔬 ¿Cómo se Resuelve el Problema de Recursos y Subproductos?

En juegos de factoría como Satisfactory, recetas como la producción de aluminio:
- **Alumina Solution**: $12 \text{ Bauxite} + 18 \text{ Water} \to 12 \text{ Alumina Solution} + 5 \text{ Silica}$
- **Aluminum Scrap**: $4 \text{ Alumina Solution} + 2 \text{ Coal} \to 6 \text{ Scrap} + 2 \text{ Water}$ *(¡Produce agua como subproducto!)*

Crean un grafo cíclico de dependencia donde parte del agua necesaria para la solución proviene del scrap. Si un calculador usase un árbol descendente simple, caería en una recursión infinita o duplicaría el agua requerida.

Nuestra implementación utiliza el **método Simplex**:
1. Para cada receta $j$, la variable $x_j \ge 0$ representa la tasa de funcionamiento (número de máquinas).
2. Para cada recurso o ítem intermedio $i$:
   $$\sum_{j} (\text{Producción}_{i,j} - \text{Consumo}_{i,j}) x_j \ge \text{Demanda}_i$$
3. Dado que las materias primas extraídas de la naturaleza tienen un costo positivo en la función objetivo y las recetas de transformación un costo infinitesimal de maquinaria, el resolutor **prioriza automáticamente reciclar el agua y los subproductos existentes** para satisfacer la demanda antes de solicitar nueva extracción de fuentes vírgenes.
4. El excedente no reciclable se clasifica como subproducto y se le asigna recomendación de drenado o triturado en el **AWESOME Sink**.

