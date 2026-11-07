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

6. **🗺️ Radar Espacial y Recomendador de Ubicaciones Óptimas (Satisfactory 1.0)**:
   - **Particionado Automático de Sub-Fábricas**: Analiza el grafo de producción DAG y agrupa cadenas de procesos según las cuencas de materias primas vírgenes (ej. Cuarzo por un lado, Acero + Hormigón por otro, Ensamblajes de alta complejidad co-localizados).
   - **Base de Datos Oficial de 608 Nodos de Recursos**: Coordenadas espaciales exactas de Unreal Engine ($X, Y, Z$), tipo de mineral, pureza (*Impure, Normal, Pure*) y bioma.
   - **Motor Matemático de Optimización Espacial**: Calcula el centroide ponderado en 3D, evalúa el costo logístico de transporte en base al flujo ($\text{items/min} \times \text{distancia}$) y selecciona los mejores clústeres del mapa.
   - **Top 3 Ubicaciones con Diversidad Geográfica**: Asegura un mínimo de 500 metros de separación entre las 3 mejores opciones por si alguna zona ya está ocupada por el jugador.
   - **Radar Vectorial Táctico en SVG**: Mapa del mundo con soporte para pan & zoom, marcadores de nodos activos con halos de pureza, balizas de sub-fábricas, líneas de alimentación a centroides y rutas logísticas inter-módulo clasificadas por modo de transporte recomendado (Cintas $<400$m, Camiones $400$m-$1.5$km, Trenes/Drones $>1.5$km).
   - **Interacción Reactiva**: Selector interactivo de opciones (#1 Óptima, #2, #3) por módulo que actualiza instantáneamente las balizas y rutas en el mapa.

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
│   ├── raw_data.json          # Dataset completo Satisfactory 1.0 (recetas, ítems, máquinas)
│   └── map_nodes.json         # 608 nodos de recursos oficiales 1.0 (X, Y, Z, pureza, bioma)
├── src/
│   ├── types.nim              # Modelos de datos (Item, Recipe, FactoryPlan, SubFactoryModule, etc.)
│   ├── dataset.nim            # Carga e indexación estática de recetas, ítems y nodos del mapa
│   ├── simplex.nim            # Motor de Programación Lineal (Simplex Dual) en Nim
│   ├── planner.nim            # Generador del plan de fábrica, análisis de subproductos y DAG
│   ├── locator.nim            # Particionado en sub-fábricas y motor de optimización espacial
│   ├── presets.nim            # Presets preconfigurados para fases del Space Elevator y fábricas
│   ├── svg_graph.nim          # Generador de gráficos de flujo vectoriales (DAG)
│   ├── svg_map.nim            # Renderizador del radar vectorial táctico del mapa del mundo
│   ├── ui.nim                 # Interfaz de usuario interactiva y componentes DOM
│   └── main.nim               # Punto de entrada de la aplicación
├── web/
│   ├── index.html             # Página web principal
│   ├── style.css              # Estilos FICSIT oscuros con detalles en naranja (#FA9549)
│   └── app.js                 # Código JavaScript compilado por Nim
├── scripts/
│   ├── build.sh               # Script de compilación rápida
│   ├── serve.sh               # Servidor local compatible con WSL
│   └── fetch_nodes.py         # Extractor del dataset de 608 nodos oficiales de Satisfactory 1.0
├── tests/                     # Suite completa de tests de validación unitaria y de integración
└── README.md                  # Este documento
```

---

## 🗺️ ¿Cómo Funciona el Recomendador Espacial de Ubicaciones?

Cuando planificas una fábrica grande (por ejemplo, *Modular Engines* o *Encased Industrial Beams* con *Quartz Crystals*), construir todo en un único punto puede ser ineficiente si los recursos naturales están dispersos por el mundo. El recomendador resuelve esto en 3 fases:

1. **Particionado de Sub-Fábricas por Cuencas de Extracción (`locator.nim`)**:
   - Analiza el DAG de producción desde las materias primas hacia arriba.
   - Detecta cuencas disjuntas o semi-independientes: por ejemplo, las recetas que requieren *Raw Quartz* forman una sub-fábrica primaria de Cuarzo, mientras que las que requieren *Iron Ore*, *Coal* y *Limestone* forman una sub-fábrica siderúrgica y de hormigón.
   - Si existen recetas complejas que combinan productos de múltiples sub-fábricas sin requerir minería directa, se aíslan como **Módulos de Ensamblaje Final** y se co-localizan con el módulo que provee la mayor masa de insumos ($\text{items/min}$).

2. **Optimización Espacial sobre Nodos 1.0 (`map_nodes.json`)**:
   - Para cada sub-fábrica, evalúa candidatos en el mapa considerando la pureza de cada nodo (*Impure* $\times 0.5$, *Normal* $\times 1.0$, *Pure* $\times 2.0$) y la velocidad de extracción del minero configurado (*Miner Mk.1/2/3* y *Overclock*).
   - Acumula los nodos más cercanos de cada mineral hasta cubrir el 100% de la demanda y calcula el **centroide ponderado 3D**:
     $$C = \frac{\sum_k w_k \cdot P_k}{\sum_k w_k}$$
   - Calcula el coste de transporte logístico con penalización por elevación vertical ($\Delta Z$):
     $$\text{Costo} = \sum_k w_k \cdot \left(\sqrt{\Delta x_k^2 + \Delta y_k^2} + 0.2 \cdot |\Delta z_k|\right)$$
   - Aplica un filtro de dispersión para asegurar al menos **500 metros** de separación euclídea entre las opciones #1, #2 y #3.

3. **Visualización y Logística en el Radar FICSIT (`svg_map.nim` y `ui.nim`)**:
   - Representa el mundo de Satisfactory (límites $X: [-324.6, 425.3]\text{ km}$, $Y: [-375.0, 375.0]\text{ km}$) en un radar SVG táctico.
   - Muestra las balizas de cada sub-fábrica, las líneas de cintas desde los nodos al centroide y las rutas inter-fábrica recomendando el sistema óptimo:
     - 🟡 **Cintas Transportadoras (Conveyor Belts)**: Distancias cortas ($< 400\text{ m}$).
     - 🚚 **Tractores / Camiones**: Distancias medias ($400\text{ m} - 1.5\text{ km}$).
     - 🚆 **Red Ferroviaria / Drones**: Distancias largas ($> 1.5\text{ km}$).

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

