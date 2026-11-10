# Decisiones de Kortex

Kortex es un monitor de sistema con dos apps: un plasmoide para el panel de KDE Plasma 6, en `linux/`, y una app para la barra de menú de macOS, en `macos/`. Las dos hacen lo mismo, se llaman igual y dicen lo mismo. Cada diferencia está escrita en su sección, como "Solo en Linux" o "Solo en macOS", con su razón. Ante una diferencia nueva gana la versión más correcta, y se lleva a la otra plataforma.

## Objetivo

Monitor de sistema siempre a la vista. La barra muestra RAM, CPU, GPU y temperatura como texto compacto; al hacer clic se abre un detalle con pestañas.

## Nombre

El nombre visible es **Kortex**; `kortex` es el nombre del proyecto y del repositorio. El id es `local.kortex` en las dos plataformas:

- **Linux:** el plasmoide es `local.kortex` y el servicio publica `local.Kortex` en el bus de sesión.
- **macOS:** el bundle es `local.kortex` y el ayudante de ventiladores, `local.kortex.fans`. La app muestra su icono en el Dock, que se puede ocultar desde Ajustes; el elemento de la barra de menú no lleva icono, solo texto.

## Prioridad

Consumo mínimo de recursos, con la RAM por delante. En macOS pesa todavía más: el equipo corre modelos locales, que comparten la memoria unificada con el resto del sistema.

## Equipos

- **Linux:** CachyOS con KDE Plasma 6.8 en Wayland. Intel Core i5-11400F (6 núcleos, 12 hilos, de 0,8 a 4,4 GHz), 32 GB de RAM con swap en zram y NVIDIA GeForce RTX 3060 de 12 GB.
- **macOS:** Mac con Apple Silicon, 24 GB de memoria unificada, macOS 27.

## Alcance

Kortex existe por lo que los monitores del sistema no dan:

- Un solo elemento con las cuatro métricas y la temperatura máxima de CPU y GPU, suavizada.
- El detalle con las apps agrupadas, la búsqueda y el cierre de procesos con confirmación.
- El consumo propio a la vista.
- Menos memoria y CPU para los mismos datos.

En Linux, Plasma ya trae widgets de Monitor del sistema que muestran sensores como texto en el panel, y la app Monitor del sistema para los procesos; Kortex existe por lo que esos widgets no dan.

- **Solo en macOS, la pestaña Batería:** el PC no tiene batería de sistema, y la del mouse la muestra el widget de batería de Plasma.
- **Solo en macOS, el mando de los ventiladores:** en el PC los llevan la BIOS y la GPU, y Kortex solo los muestra.
- **Consumo eléctrico en Linux:** solo el de la GPU, en su pestaña. El de la CPU (RAPL) solo lo lee root, y el PC no tiene sensores de corriente ni de consumo total.

## Stack

### Linux

- **Plasmoide:** QML para Plasma 6, con los componentes de Plasma y Kirigami. Corre dentro de plasmashell, sin proceso propio, y arranca con la sesión.
- **Servicio:** Rust, sin dependencias externas. Usa sd-bus de libsystemd para D-Bus y carga NVML con `dlopen`, así que funciona aunque falte el controlador de NVIDIA. Compila a un binario de unos 430 KB.
- **Comunicación:** bus de sesión. El plasmoide pide los datos con sus temporizadores y el servicio responde con JSON. El servicio no tiene temporizador propio y termina tras 60 s sin pedidos; D-Bus lo vuelve a lanzar con el siguiente.

La bandeja del sistema de Plasma (StatusNotifierItem) muestra solo iconos, nunca texto, así que el texto en el panel necesita un plasmoide.

### macOS

- **Lenguaje:** Swift.
- **Interfaz:** AppKit puro (`NSStatusItem` para la barra de menú y un `NSPanel` propio para la ventana de detalle), sin SwiftUI.
- **Compilación:** Swift Package Manager con las Command Line Tools, sin Xcode.

Swift con AppKit compila a un binario nativo sin runtime adicional y accede directamente a las APIs del sistema.

Los textos, botones, selectores, interruptores e iconos del detalle son vistas propias que se dibujan solas, sin controles de AppKit (`NSTextField`, `NSButton`, `NSSegmentedControl`, `NSSwitch`) ni SF Symbols. `NSTextField` guarda la medida de cada texto distinto que muestra en una caché sin límite, unos 330 bytes por texto, y el detalle cambia sus valores cada pocos segundos; los SF Symbols cargan catálogos del sistema que quedan en memoria, unos 0,5 MB. Cada vista declara su función de accesibilidad, así que VoiceOver la reconoce como texto, botón, selector o interruptor.

La ventana de detalle es un panel sin borde que no activa la app. `NSPopover` no sirve para ella: en macOS 27, cada vez que cambia de tamaño y de contenido a la vez, el sistema le reserva unos 90 MB de memoria gráfica durante un segundo, y al cerrarse deja unos 13 MB que crecen con cada apertura.

## Consumo

### Reglas comunes

- La barra es la única lectura permanente. Lee solo totales del sistema y nunca recorre los procesos.
- El detalle se crea al abrirse y se libera al cerrarse. Cada pestaña se crea al entrar en ella.
- Los totales del detalle y los valores de las pestañas se actualizan al ritmo de la barra; las listas, las zonas de temperatura y los ventiladores, al ritmo del detalle.
- Al abrir el detalle, al cambiar de pestaña y al pulsar Actualizar se hace una lectura inmediata.
- Solo se calculan los datos de la pestaña visible.
- Las lecturas se pausan con la pantalla bloqueada.
- Una función que no cumpla las metas se revisa antes de darla por terminada.

### Linux

**Referencia.** Los widgets de Monitor del sistema leen la GPU a través de ksystemstats, que lanza `nvidia-smi dmon`: 26,9 MB de PSS y 0,2 % de CPU constante, además de los 8,2 MB de ksystemstats, que corre siempre. Kortex tiene que costar menos que eso para los mismos datos.

**Medido** con `tools/measure.py`, en el propio equipo, con el escritorio en uso. La CPU suma el servicio y el plasmoide corriendo en `plasmawindowed`, que reproduce lo que el plasmoide hace dentro de plasmashell:

| Estado | CPU |
|---|---|
| Barra cada 1 s | ~0,1 % |
| Barra cada 10 s | ~0,01 % |
| Detalle abierto en RAM, lista cada 10 s | ~0,25 % |
| Detalle abierto en RAM, lista cada 1 s | ~0,65 % |

El servicio ocupa 26,4 MB de PSS. De eso, 20,5 MB son de NVML: al iniciarse carga `libcuda` y ocupa una región de 18,9 MB que no devuelve ni al cerrarse. El resto, unos 6 MB, es el propio servicio con su parte de las bibliotecas compartidas. Las listas de procesos suman unos 150 KB mientras el detalle está abierto y se liberan al cerrarlo.

Cada lectura del servicio cuesta: la barra, 0,33 ms; los totales de la pestaña GPU, 2,8 ms; la lista de RAM o de CPU, 3,2 ms; la de GPU, 6 ms; la de Temp, 2,8 ms.

Dentro de plasmashell, la primera apertura del detalle suma entre 14 y 21 MB de PSS que quedan reservados al cerrarlo, y las siguientes, de 1 a 3 MB. Un detalle vacío suma unos 10 MB: es lo que cuesta la ventana emergente de Plasma. Quitar la lista de apps, o crear sus botones solo al pasar el ratón, no lo reduce de forma medible: la variación entre reinicios de plasmashell es mayor que lo que pesan. Como referencia, el calendario del reloj de Plasma suma más de 40 MB en su primera apertura.

Reglas propias:

- El detalle se libera un segundo después de cerrarse.
- Al cerrar el detalle, el plasmoide avisa con `Close`, y el servicio suelta las listas de procesos y devuelve la memoria al sistema con `malloc_trim`. Si el aviso no llega, las suelta en la primera lectura de la barra que llegue 30 s después del último pedido del detalle.
- Varios Kortex en la sesión comparten la lectura de la barra: el servicio emite cada lectura como la señal `Reading` y todos la escuchan. Con el detalle cerrado, cada uno pide una lectura solo si no le llegó ninguna en su intervalo menos medio segundo, así que consulta el de intervalo más corto y los demás muestran sus lecturas a su propio ritmo.
- El plasmoide sabe que la pantalla está bloqueada por la señal `ActiveChanged` de `org.freedesktop.ScreenSaver`.

### macOS

**Metas:**

| Estado | RAM | CPU |
|---|---|---|
| Ventana de detalle cerrada, barra de menú cada 3 s | < 12 MB | < 0,35 % |
| Ventana de detalle abierta | < 15 MB | — |

Con la ventana de detalle cerrada, el gasto de CPU lo marca el repintado del elemento en la barra de menú, no las lecturas: leer todos los sensores cuesta 0,017 % y el resto lo pone macOS al dibujar la barra de menú en cada pantalla conectada.

Con la pestaña de RAM o CPU abierta, leer todos los procesos cuesta más: la lista de RAM ronda el 4 % de CPU con el detalle cada 7 s; sube al bajar el intervalo y baja al subirlo. Con la ventana de detalle cerrada esa lectura no se ejecuta.

**Medido** en el equipo de destino, con su pantalla y un monitor externo, con la barra de menú cada 3 s y el detalle cada 7 s, con `scripts/measure.sh` en la pestaña RAM:

| Estado | RAM | CPU |
|---|---|---|
| Ventana de detalle cerrada, sin haberla abierto | 8,3 MB | 0,2 % |
| Ventana de detalle abierta | 9,7–10 MB | según la pestaña |
| Ventana de detalle cerrada, después de abrirla | 8,9 MB | 0,2 % |

Cada pantalla conectada suma una barra de menú donde macOS dibuja el elemento, y mueve tanto la RAM como la CPU.

Mostrar u ocultar el icono del Dock no cambia estas cifras. El máximo medido con la ventana de detalle abierta es 11 MB, con la lista de RAM expandida. Al cerrarla, la memoria baja en pocos segundos y queda menos de 1 MB por encima del arranque: cachés que AppKit y macOS crean la primera vez que se abre (métodos, glifos, la sesión de entrada de texto de la ventana) y huecos entre objetos vivos. Esa diferencia no crece con el uso: 40 aperturas por todas las pestañas y 10 reconexiones de una pantalla virtual dejan la app en 9,6 MB. Para que siga así, las listas reutilizan sus filas y la lectura de procesos reserva lo mínimo. Desconectar y volver a conectar el cable o el dock de los monitores deja en la app una ventana de la barra de menú que macOS no libera, de unos 70 KB; apagar y encender un monitor no deja ninguna. La app no puede liberarla: quitar y volver a crear el elemento de la barra deja viva otra ventana del elemento quitado.

CPU con cada pestaña abierta, con la pantalla del equipo y dos monitores externos y el detalle cada 7 s, incluidos `top` y `ps`. La media es de un minuto y el pico, del tramo de 3 s más alto:

| Pestaña abierta | CPU media | Pico |
|---|---|---|
| RAM | 4,3 % | 9,3 % |
| CPU | 2,3 % | 4,9 % |
| GPU | 1,8 % | 3,9 % |
| Temp | 0,6 % | 0,8 % |
| Batería | 2,0 % | 4,3 % |

La de RAM es la más cara porque `top` recorre todos los procesos del sistema.

Mientras la curva manda los ventiladores, el ayudante suma 1,8 MB y 0,0 % de CPU, y el pie los incluye. De esos 1,8 MB, 1,7 son el suelo de cualquier proceso que abra IOKit, en C o en Swift.

**Asignador de memoria.** La app arranca con `MallocSpaceEfficient=1`, `MallocMaxMagazines=1` y `LIBDISPATCH_CONTINUATION_ALLOCATOR=0`, declarados en `LSEnvironment` del `Info.plist`. El asignador por defecto de macOS 27, xzone malloc, separa los bloques por tipo y por núcleo y conserva sucias las páginas que libera: con él, la app mide 14 MB al arrancar y 18 MB después de abrir el detalle. El modo eficiente usa un solo almacén y marca como reutilizables las páginas vacías, que salen de la memoria de la app; libdispatch, sin su reserva propia por núcleo, toma de `malloc` la memoria de sus tareas.

El modo eficiente no tiene el aislamiento por tipo de xzone, una defensa contra la explotación de errores de memoria. La app solo lee datos del sistema y está escrita en Swift, así que el ahorro lo compensa.

`LSEnvironment` se aplica cuando la app se abre por LaunchServices: Finder, inicio de sesión u `open`. Por eso `scripts/measure.sh` la abre con `open`.

**Color.** Todas las ventanas de la app dibujan en sRGB, el espacio de todos sus colores, y macOS los ajusta a cada pantalla al componerlas. Así la app no convierte colores al perfil de cada monitor. Core Graphics guarda unas 15 conversiones entre espacios de color; con un perfil de curvas paramétricas, como el que macOS genera para algunos monitores externos, cada una reserva tablas de 272 KB por canal y ocupa unos 64 KB. Cada reconexión de un monitor le da un espacio de color nuevo, y AppKit calcula su gama al despertar o recolorear una ventana en él, así que cada reconexión suma una o dos conversiones hasta llenar esa caché.

Reglas propias:

- Las listas de apps reutilizan sus filas en cada lectura.
- Los colores y los textos con formato de la barra de menú se crean una sola vez y se reutilizan en cada dibujo.
- La ventana de detalle no lleva campos de texto editables: el buscador de las listas es una vista dibujada que recibe las teclas de la ventana.
- `top` corre únicamente para la lista de RAM del detalle, y solo mientras esa pestaña está abierta.
- La presión de memoria llega por evento del sistema, sin consulta periódica.
- Las lecturas también se pausan con la pantalla apagada, y los temporizadores usan tolerancia para agruparse con los despertares del sistema. Con la curva de ventiladores activa, la temperatura es lo único que se sigue leyendo con la pantalla apagada.

## Barra

Un solo elemento, sin iconos, con cuatro columnas de dos líneas: el nombre arriba y el valor abajo, cada columna en el color de su métrica. Orden:

```
RAM   CPU   GPU   TEMP
22%   12%   3%    59°C
```

- **RAM:** memoria usada, en % sobre el total.
- **CPU:** uso sobre todos los núcleos o hilos.
- **GPU:** uso de la GPU.
- **TEMP:** máximo entre los sensores de CPU y GPU, promediado sobre las tres últimas lecturas, sin decimales. El máximo refleja el punto más caliente, el que determina el throttling, e incluye la GPU.

Cada columna mide lo que su contenido, con el ancho del nombre como mínimo. El valor reserva siempre dos dígitos con números tabulares, así que el elemento solo cambia de ancho cuando una métrica llega a tres dígitos. Un lector de pantalla recibe los cuatro valores en una frase ("RAM 22%, CPU 12%, GPU 3%, TEMP 59°C").

Un clic abre el detalle en la última pestaña usada, también después de reiniciar; la primera vez abre en RAM. Ajustes no cuenta como pestaña. Otro clic, un clic fuera, Esc o pasar a otra ventana lo cierran.

- **Solo en Linux:** es el panel, y Ajustes la llama "barra". Las columnas se separan por 1,5 veces el espaciado pequeño de Kirigami (6 px); en un panel vertical se apilan, separadas por dos veces el espaciado pequeño. El nombre va en peso medio al 85 % de la letra pequeña del tema y el valor, al 90 % de la letra normal, con el renderizado nativo con hinting de FreeType, que a estos tamaños en una pantalla a escala 1 deja los trazos más nítidos que el de QtQuick. El nombre queda a 2 px sobre el valor, medidos entre las letras visibles, y el bloque se centra según esas letras. Como el reloj, el bloque ocupa el 90 % del alto que Plasma le da al elemento y no pasa de 1,25 veces esos tamaños, así que mide lo mismo que el reloj en un panel de 1× (32 px útiles) y en uno 4K a 1,4× (24 px útiles). Mientras el detalle está abierto, Plasma lo marca con su propio indicador, de 3 px, en el margen del panel.
- **Solo en macOS:** es la barra de menú. El nombre va a 8 pt y el valor a 11 pt, con 6 pt entre columnas. El bloque se centra por la altura de las mayúsculas y queda a la misma altura que el reloj del sistema. Mientras el detalle está abierto, el elemento lleva una cápsula de fondo, como los menús del sistema.

## Detalle

Pestañas **RAM, CPU, GPU y Temp**. Cada pestaña muestra su nombre y, debajo, su valor en vivo en el color de su métrica, así que las cuatro métricas se ven sin cambiar de pestaña. Debajo, cada pestaña abre con su valor en grande, en su color, a la izquierda, y un dato de contexto a la derecha.

- **Solo en macOS, la pestaña Batería:** el PC no tiene batería.
- **Linux:** ventana emergente de Plasma, de tamaño fijo e igual en todas las pestañas: 20 × 28 unidades de Kirigami (360 × 504 px con la letra por defecto), sin pasar del alto disponible de la pantalla. Mientras una lista muestra más que sus 5 apps plegadas, la ventana se alarga en 5,5 filas: con "Mostrar más", con una app desplegada o con una búsqueda que despliega apps. El panel está abajo y la ventana crece hacia arriba, así que con un alto variable las pestañas se moverían al cambiar de una a otra. Plasma 6 guarda el tamaño de cada ventana emergente; el detalle fija el mínimo y el máximo en ese tamaño, de modo que no se puede redimensionar. El texto va al 90 % de la letra del tema, con márgenes de 8 px; la lista ocupa el alto que queda y hace scroll dentro.
- **macOS:** se abre 6 pt por debajo de la barra de menú, centrada en su elemento y sin salirse de la pantalla, con esquinas de 12 pt, borde de 0,5 pt y sombra, sin flecha. Crece y encoge hacia abajo, con el borde superior fijo, así que se ajusta a su contenido en cada lectura, al cambiar de pestaña y al desplegar o plegar, y el pie siempre queda abajo. El alto máximo es el alto visible de la pantalla; si el contenido no cabe, hace scroll. Las listas tienen scroll interno de unas 10 filas; al llegar a su borde, el desplazamiento del trackpad pasa a la ventana. No activa la app: la barra de menú sigue mostrando los menús de la app que se estaba usando.

### RAM

- Encabezado: porcentaje usado, y a la derecha usada / total ("8,27 GB / 31,21 GB").
- Barra de cinco tramos que suma el total, con una fila por tramo:
  - **Apps:** memoria de los procesos. Linux: `AnonPages` + `Shmem`. macOS: páginas internas menos las purgables.
  - **Sistema:** núcleo y controladores. Linux: el resto de la memoria usada, tablas de páginas incluidas. macOS: memoria fija (`wire_count`).
  - **Comprimida:** Linux: RAM que ocupa la swap comprimida en zram (`mem_used_total`). macOS: páginas del compresor.
  - **Caché:** lo que el sistema puede recuperar. Linux: `MemAvailable` − `MemFree`. macOS: páginas de archivos y purgables.
  - **Libre:** lo que queda.
- **Swap:**
  - **Linux:** "usada / total", en ámbar cuando hay páginas en una swap de disco. La swap en zram está en la RAM, y el kernel la llena con páginas sin uso aunque sobre memoria, así que se muestra en el color del texto.
  - **macOS:** solo la usada, en ámbar cuando es mayor que 0. La swap de macOS son archivos que crecen solos, así que un total no significa nada.
- **Presión:**
  - **Linux:** el `some avg10` de `/proc/pressure/memory`, el porcentaje de los últimos 10 s en que alguna tarea esperó memoria. Normal (verde) por debajo del 10 %, Advertencia (ámbar) desde el 10 % y Crítica (rojo) desde el 60 %.
  - **macOS:** el nivel que da el kernel: Normal, Advertencia o Crítica.
- Lista de apps por memoria.

### CPU

- Encabezado: uso total. **Linux:** a la derecha, núcleos · hilos.
- Barra de uso.
- **Linux:** frecuencia media de los hilos · máxima, en GHz con dos decimales. macOS no la lee.
- **macOS:** uso por grupo de núcleos (Super · Performance), con los nombres y el tamaño de cada grupo que da el sistema.
- Lista de apps por CPU. Sus porcentajes son por hilo o núcleo: 100 % es uno ocupado, así que una app con varios procesos puede pasar del 100 %. El total de la pestaña y el de la barra son sobre todos.

### GPU

- Encabezado: uso total, y a la derecha el nombre de la GPU.
- Barra de uso.
- Frecuencia actual · máxima, en GHz con dos decimales.
- Consumo en W.
- Memoria en uso.
- Temperatura.
- Núcleos.
- Lista de apps por GPU.

Cada plataforma muestra los datos que da su API:

- **Linux (NVML):** codificador · decodificador, controlador de memoria, consumo · límite de potencia, memoria de vídeo en uso · total. La lista muestra el uso medio de los multiprocesadores en las muestras de NVML del intervalo, y la memoria de vídeo de cada app.
- **macOS (IOAccelerator, IOReport y Metal):** renderizado · tiler, memoria en uso · asignada, y el máximo que macOS permite usar a la GPU. La temperatura es el máximo de los sensores de GPU que ya lee la barra. La lista muestra solo el porcentaje.

Un valor que el sistema no da se muestra como "—".

### Temp

- Encabezado: la temperatura de la barra, sin decimales, y a la derecha "Máximo de CPU y GPU".
- "Zonas · máximo · promedio", con un decimal. Las zonas salen de los sensores de cada equipo:
  - **Linux:** CPU (coretemp), GPU (NVML), Placa, SSD (NVMe), Red y Otros.
  - **macOS:** CPU, GPU, Memoria, SSD y Batería (claves del SMC).
- Ventiladores: una fila por ventilador, con sus RPM o "Parado".
  - **Linux:** los dos de la GPU ("GPU 1", "GPU 2") con su porcentaje, que da NVML, y los de la placa cuando su controlador está cargado.
  - **macOS:** "Ventilador 1", "Ventilador 2", y debajo el mando (ver Ventiladores).

### Batería (solo macOS)

- Porcentaje en el encabezado, con barra, estado (conectado, cargando, descargando) y tiempo restante. Mientras carga o descarga, el estado dice a cuántos vatios, redondeado y desde 1 W: "Conectado · cargando a 49 W", "Con batería · descargando a 16 W". Es la potencia de la batería de Energía.
- Modo de energía de la fuente actual y modo de la otra fuente. Solo lectura.
- Lista de apps por energía, con dos decimales porque los valores por proceso son pequeños.
- Estado: salud y condición, ciclos sobre el máximo de diseño, capacidad actual · diseño, temperatura. La salud es el porcentaje que informa la propia batería y la condición es Normal por encima del 80 %. La capacidad actual es la de carga completa de hoy, frente a la de diseño. La temperatura viene de los sensores de la zona de batería.
- Energía: consumo del sistema, potencia de la batería, voltaje · corriente.
- Adaptador: el nombre que informa, o "Adaptador USB-C" cuando no informa ninguno, con la potencia que entrega sobre la que declara el propio adaptador ("61,3 / 94 W"), y el voltaje · corriente que entrega. El de 96 W declara 94 W, lo máximo que ofrece al Mac (20 V × 4,69 A). Mientras macOS no informa la entrega, esos valores muestran "—". Solo con el adaptador conectado.

### Listas de apps

Mismo comportamiento en todas las listas:

- Los procesos se agrupan por app, y el grupo lleva el nombre de su raíz. Las apps se ordenan por consumo y, a igual consumo, por nombre. Un clic en el nombre despliega sus procesos con sangría y una línea vertical, en la misma letra que la app.
  - **Linux:** dos procesos van al mismo grupo si comparten unidad de systemd (cgroup) o si uno desciende del otro. Un proceso de los servicios de la sesión (`session.slice`), de `init.scope` o del scope de inicio de sesión no arrastra a sus hijos. Así, las apps que lanza Plasma quedan cada una en su grupo aunque repartan sus procesos en dos unidades, como Chromium.
  - **macOS:** cada proceso cuelga del proceso raíz del que desciende, subiendo por el árbol de padres hasta el último que depende del sistema. Así los ayudantes de una app quedan bajo ella y cada demonio del sistema queda solo en su grupo.
- Las listas de RAM y CPU incluyen todos los procesos, del sistema y del usuario, también los que están en 0 %. Las de GPU y energía incluyen los que tienen consumo medible.
- **Memoria de cada proceso:**
  - **Linux:** su memoria privada residente (`RssAnon`), la única que se puede leer de los procesos de otros usuarios.
  - **macOS:** la memoria real que da `top`.
- Muestran 5; "Mostrar más", un botón simple a la izquierda, amplía hasta 50 y "Mostrar menos" vuelve a 5. El encabezado dice "Apps · 5 de 62", con el total real o, con búsqueda, las coincidencias. Antes de la primera lectura dice solo "Apps". Una lista vacía dice "Ninguna app en uso", y una búsqueda sin resultados, "Ninguna app coincide".
- **Alcance de "Mostrar más" y de las apps desplegadas:**
  - **Linux:** valen para todas las listas mientras el detalle sigue abierto, porque la ventana tiene alto fijo y no debe saltar entre pestañas.
  - **macOS:** cada lista recuerda los suyos, porque la ventana se ajusta al contenido.
- A la derecha del encabezado, un buscador con el texto "Escribe para buscar".
  - **Linux:** el buscador recibe el foco al abrir la pestaña.
  - **macOS:** lo que se escribe con la ventana abierta va al buscador sin pulsarlo antes. Borrar quita la última letra y la ✕ vacía la búsqueda.
- La búsqueda filtra por nombre sin distinguir mayúsculas ni acentos e ignora los espacios del principio y del final. Una app aparece si coincide su nombre o el de alguno de sus procesos; si solo coinciden procesos, aparece desplegada con esos procesos, y se puede plegar. La búsqueda es la misma en todas las listas y se borra al cerrar el detalle.
- Esc cierra primero la confirmación abierta, después vacía la búsqueda y, con la búsqueda vacía, cierra el detalle.
- Al pasar el cursor aparece una ✕ para cerrar. Los procesos que Kortex no puede cerrar muestran un candado del mismo tamaño, y también la app cuyo proceso raíz no puede cerrar; sus procesos propios se cierran uno por uno. Mientras la confirmación está abierta, la ✕ queda en rojo y la fila, marcada.
  - **Linux:** no se pueden cerrar los procesos de otros usuarios ni los de la sesión.
  - **macOS:** no se pueden cerrar los procesos de otros usuarios.
- La ✕ abre una confirmación en línea, a todo el ancho, con la pregunta arriba, en tantas líneas como haga falta, y los botones debajo:
  - App con varios procesos: "¿Cerrar X y todos sus procesos?" · **Cancelar** · **Cerrar app** · **Forzar cierre**.
  - App con un solo proceso, o un proceso suelto: "¿Terminar X?" · **Cancelar** · **Terminar proceso** · **Forzar cierre**.
- Cerrar app alcanza a todos los procesos propios del grupo, aunque la lista no los muestre. Cerrar app y Terminar proceso envían `SIGTERM`; Forzar cierre, `SIGKILL`. Antes de cada señal, Kortex comprueba que el proceso siga siendo el mismo, por su hora de inicio, y que sea del usuario. El cierre por señal no ofrece guardar los cambios pendientes de la otra app.
- Hay una sola confirmación abierta a la vez; se cierra al abrir otra, con un segundo clic en la misma ✕, al cambiar de pestaña, al entrar en Ajustes o con Esc.

### Pie

Bajo el encabezado "Consumo de Kortex", dos filas: **Con la ventana abierta** ("26,04 MB RAM · 0,67% CPU") y **Con la ventana cerrada**. Cada número va en el color de su métrica, y "RAM", "CPU" y el separador, en gris. La CPU lleva siempre dos decimales. La fila cerrada muestra la última lectura con el detalle cerrado, y su CPU sale solo de intervalos en que el detalle estuvo cerrado de principio a fin.

- **Linux:** la RAM es el PSS del servicio y la CPU, su tiempo de CPU entre dos lecturas de la barra. Lo que el plasmoide gasta dentro de plasmashell no se puede separar del resto de plasmashell y no está incluido. Si el servicio no responde, una línea en rojo lo dice.
- **macOS:** incluye los subprocesos que lanza la app. La primera fila cambia con la pestaña: la lista de RAM la eleva y las demás la dejan baja. Un `top` que la lista de RAM lanzó antes de cerrar puede terminar después y sumar unos 6 % en un intervalo de 3 s, así que la fila cerrada descarta los intervalos en que terminó un subproceso.

Al final, **Actualizar · hace X s** ("ahora" con menos de 1 s) contra el borde izquierdo y **Ajustes** contra el derecho. Actualizar hace una lectura completa en el momento. En Ajustes el pie sigue visible, sin el botón Ajustes, para ver el efecto de cada intervalo. **Solo en macOS, Salir**, en la esquina: un plasmoide no se cierra.

### Ajustes

- Título "‹ Ajustes" con **Restablecer** en el extremo derecho.
- Actualizar la barra cada: 1, 2, 3, 5, 7 o 10 s. Por defecto, 3 s. En macOS dice "la barra de menú".
- Actualizar el detalle cada: 1, 2, 3, 5, 7 o 10 s. Por defecto, 3 s.
- Bajo cada selector, en letra chica y gris, el costo en la forma "Usa ~X% de CPU", con dos decimales por debajo de 0,1 % y uno desde ahí; en el detalle añade "con la lista de RAM abierta". El costo sale de lo medido en cada equipo:
  - **Linux:** en la barra, 0,1 % dividido por el intervalo; en el detalle, 0,25 % fijo más 0,4 % dividido por el intervalo.
  - **macOS:** en la barra, 0,7 % dividido por el intervalo; en el detalle, 0,8 % fijo más 24,4 % dividido por el intervalo, con la pantalla del equipo y dos monitores externos.
- **Solo en macOS, "Sistema":** Abrir al iniciar sesión (por defecto, desactivado) y Mostrar icono en el Dock (por defecto, activado). Sin el icono, Kortex vive solo en la barra de menú y el cambio se aplica sin cerrar la ventana de detalle.
- Al final, "Kortex" y la versión, en letra chica y gris.

Restablecer vuelve todo a sus valores por defecto. Los selectores no marcan el valor por defecto. Los cambios se aplican y se guardan al instante.

## Ventiladores

### Linux

En `/sys/class/hwmon` no aparece ningún ventilador de la placa: su controlador Super I/O no está cargado. Los dos ventiladores de la GPU se leen con NVML, y con la GPU fría están parados. Los controlan la BIOS y la propia GPU; Kortex solo muestra su velocidad. Si se carga el controlador de la placa (`nct6775` o `nct6683`), sus `fan*_input` aparecen solos en la pestaña Temp.

### macOS

El equipo lleva dos ventiladores de 2317 a 7826 RPM. Debajo de su velocidad, la pestaña Temp muestra quién los manda:

- **Automático:** los lleva macOS con su propia curva. Es el valor por defecto.
- **Según temperatura:** los lleva Kortex con la temperatura de la barra, así que la curva no cuesta ninguna lectura extra.

El rango lo decide el usuario: dos extremos entre 40 y 100 °C, separados al menos 5 °C, de 60 a 90 °C por defecto. Por debajo del extremo bajo manda macOS, que atiende también a la batería y al SSD y que con el chip frío deja los ventiladores parados, algo que el modo manual no alcanza: su mínimo son 2317 RPM. Por eso el mando solo pasa a Kortex dentro del rango, y al entrar los ventiladores arrancan en ese mínimo. Entre los dos extremos la velocidad sube en línea recta desde el mínimo del ventilador hasta su máximo, y por encima del extremo alto se queda en el máximo. El mando vuelve a macOS 2 °C por debajo del extremo bajo, para no entrar y salir del modo manual con cada décima.

Con "Según temperatura" aparece la curva dibujada, que es a la vez el dibujo de la regla y el mando:

- El eje de abajo es la temperatura, de 40 a 100 °C. El de la izquierda son las RPM, con rejilla desde el mínimo del ventilador hasta su máximo; el 0 queda en una franja fina al pie, porque entre 0 y el mínimo no hay velocidades que dar, y ahí va la línea gris de cuando están parados.
- Los dos círculos son los extremos del rango, cada uno con su temperatura al lado. Se arrastran en pasos de 1 °C y un clic en cualquier punto del gráfico lleva allí el más cercano.
- Una línea vertical marca la temperatura del momento, rotulada con su valor y, cuando la curva manda, con las RPM que pide; un punto sobre la rampa señala dónde cae.
- En las esquinas de abajo, qué hace cada extremo: "Empiezan a subir" y "Llegan al máximo".

Si el ayudante falta o falla, una línea bajo el gráfico lo dice y los ventiladores quedan en manos de macOS.

El objetivo se recalcula con cada lectura de la barra de menú, de modo que con el intervalo por defecto los ventiladores reaccionan en 3 s y alcanzan la velocidad pedida un segundo después. Con la pantalla apagada o bloqueada, la temperatura se sigue leyendo para que la curva no se detenga; el resto de las métricas no. Antes de que el equipo se duerma, el mando vuelve a macOS.

**Ayudante.** `KortexFans` es el único componente con root y solo existe mientras la curva manda. Kortex lo lanza como subproceso y le escribe por su entrada un byte: de 0 a 100, el nivel entre el mínimo y el máximo de cada ventilador, o 255 para devolver el mando. El ayudante abre el SMC como root, baja a los privilegios del usuario y solo los recupera para escribir `F{n}md`, el modo manual, y `F{n}Tg`, las RPM objetivo. Con cada byte comprueba que el modo siga en manual, así que recupera el mando si el sistema lo cambia.

Devuelve los ventiladores a macOS y termina en cuanto Kortex cierra la entrada, cuando Kortex desaparece (el tubo se cierra solo) y cuando pasan 30 s sin recibir nada, así que un cuelgue de la app no deja los ventiladores fijos.

## Icono

Un chip blanco con patitas sobre un cuadrado redondeado mostaza y un núcleo carbón en el centro, que alude a la RAM, la prioridad del proyecto. Colores: fondo mostaza `#E8B84A` (arriba) a `#C68A1C` (abajo); cuerpo y patitas `#FFFFFF`; núcleo `#2E2A20`. El maestro es `assets/icon/AppIcon.svg`. La barra no lleva icono, solo texto.

- **Linux:** se instala como `local.kortex` en el tema hicolor y aparece en "Añadir widgets" y en los diálogos del widget.
- **macOS:** `macos/assets/icon/AppIcon.icns` y la carpeta `AppIcon.iconset` con los seis PNG salen del maestro. El `.icns` incluye 128, 256 y 512 px en @1x y @2x, hasta 1024. No lleva 16 ni 32 px: macOS muestra esos tamaños encogidos sobre una placa, y sin ellos reduce el de 128.

## Formato

- GB y MB con dos decimales como máximo y coma decimal, sin ceros finales; GB desde 1 GiB.
- Porcentajes sin decimales; en las listas, dos decimales por debajo de 1 %; en el pie, siempre dos.
- Temperatura en grados Celsius: sin decimales y pegada al número en la barra (`59°C`); sin decimales en las pestañas y en los encabezados, y con un decimal en las zonas, separada por un espacio (`59 °C`, `59,0 °C`). Un valor que cambia en vivo lleva sus decimales fijos, para que el ancho no salte en cada lectura.
- Frecuencias en GHz con dos decimales fijos (`1,40 · 1,78 GHz`).
- Vatios con un decimal como máximo.

## Colores

Cada métrica lleva su color, en una versión para tema oscuro y otra para tema claro, que siguen el modo del sistema:

| Métrica | Oscuro | Claro |
|---|---|---|
| RAM | `#6CB2FF` | `#1E63C4` |
| CPU | `#FF7A73` | `#C4312B` |
| GPU | `#5DD98C` | `#1F8A4C` |
| Temperatura | `#F7C95C` | `#A96A00` |

Barra de RAM: Apps en el color de RAM; Sistema `#B57BF5` / `#7A34C4`; Comprimida `#34D0C0` / `#0E8A80`; Caché `#3F6C99` / `#9DC1EB`; Libre `#55555C` / `#C9C9CF` (oscuro / claro). Los tonos se separan en azul, violeta y turquesa para distinguirse a simple vista.

Botones de la confirmación: Cerrar app y Terminar proceso `#2D4A6E` / `#1E63C4` con borde `#3E679A` / `#1A57AD`; Forzar cierre `#5C2A2A` / `#C4312B` con borde `#8A3A3A` / `#A82A25`; los dos con texto blanco. Al pasar el cursor, `#355783` / `#1A57AD` y `#6C3131` / `#A82A25`.

- **Linux:** el resto (fondo, pestañas, botones, buscador, y el verde, ámbar y rojo de los estados) son los del tema de Plasma, que se decide por el brillo del fondo de Kirigami.
- **macOS:** no hay tema que seguir, así que la app trae los suyos. Datos y etiquetas en texto claro; el gris queda para los encabezados de grupo, el pie y el candado.
  - Fondo de la ventana de detalle: `#1C1C1F` / `#F6F6F8`, plano y opaco. Borde: `#3A3A3E` / `#D9D9DE`, el mismo color que las líneas separadoras.
  - Resaltado al pasar el cursor: `#33333A` / `#DEDEE6` sobre el fondo, y `#3A3A40` / `#EFEFF3` sobre la tira de pestañas. Todo lo que se puede pulsar lo lleva. Cancelar toma `#38383D` / `#DEDEE3`.
  - Tira de pestañas: `#2A2A2E` / `#E4E4E9`; la pestaña activa, `#3D3D42` / `#FFFFFF` con borde `#55555C` / `#C4C4CB`. Los selectores de Ajustes y de los ventiladores usan los mismos tonos.
  - Interruptores: encendido en el color de GPU y apagado `#55555C` / `#C4C4CB`, con la perilla blanca.
  - Swap y presión usan los colores de las métricas: GPU para Normal, temperatura para Advertencia y CPU para Crítica.
  - La cápsula de la barra de menú con el detalle abierto es `labelColor` al 12 %, el mismo tono que usa el sistema.
  - La barra de menú y la ventana de detalle cambian de modo en el momento, también con la ventana abierta.

## Permisos

Kortex no pide ningún permiso del sistema para leer ni para cerrar procesos.

- **Linux:** `/proc` y `/sys` se leen como usuario, igual que NVML. De los procesos de otros usuarios se ven el nombre, el tiempo de CPU y la memoria residente. Las señales van solo a procesos propios fuera de la sesión. Los ventiladores son de solo lectura, y la instalación no pide contraseña.
- **macOS:** todas las métricas se leen sin permiso, incluidas las RPM de los ventiladores. `top` y `ps`, que vienen con macOS, entregan el consumo de todos los procesos sin instalar nada. Las señales van solo a procesos del usuario, sin el permiso de Automatización. Abrir al iniciar sesión lo avisa macOS con una notificación y queda gestionable en Ajustes del Sistema.
- **Mandar los ventiladores (macOS):** escribir en el SMC exige root; a cualquier otro proceso le responde `kIOReturnNotPrivileged`. `scripts/install-fans.sh` copia el ayudante a `/Library/PrivilegedHelperTools/local.kortex.fans` con `sudo install -o root -g admin -m 4750`, de modo que pertenece a root, lleva el bit setuid y solo lo ejecuta el grupo `admin`. Es la única vez que se pide la contraseña de administrador, y se repite solo cuando el ayudante cambia. No se instala demonio, agente ni elemento de inicio, así que no deja registro en la gestión de tareas en segundo plano (BTM) del sistema. El ayudante solo acepta un nivel o la orden de devolver el mando a macOS.

## Instalación

### Linux

`scripts/install.sh` compila el servicio y lo instala todo en la carpeta del usuario, sin sudo:

- el binario en `~/.local/bin/kortex-service`;
- la unidad de usuario `~/.config/systemd/user/kortex.service`;
- el archivo de activación `~/.local/share/dbus-1/services/local.Kortex.service`;
- el icono `local.kortex` en el tema hicolor;
- el plasmoide, con `kpackagetool6`.

El plasmoide se agrega al panel desde "Añadir widgets". `scripts/uninstall.sh` quita todo lo anterior. `scripts/package.sh` arma el instalador de un solo archivo que publica cada release.

### macOS

macOS bloquea con Gatekeeper una app descargada que Apple no notarizó, así que no hay descarga: Kortex se compila en el propio equipo, donde macOS no la marca como descargada.

`Kortex.app` vive en `~/Applications`, la carpeta de aplicaciones del usuario: no pide contraseña de administrador y da una ruta estable para "Abrir al iniciar sesión". `scripts/build.sh` compila en release, arma el paquete y lo firma en el propio equipo. `scripts/install.sh` además reemplaza la copia instalada y la abre, y avisa cuando el ayudante instalado no coincide con el compilado. `scripts/install-fans.sh` instala el ayudante de ventiladores.

## Fuentes de datos

### Linux

| Dato | Fuente |
|---|---|
| RAM, swap | `/proc/meminfo` |
| Swap en disco | `/proc/swaps`, todas las líneas salvo `/dev/zram*` |
| RAM comprimida | `/sys/block/zram*/mm_stat`, tercer campo |
| Presión de memoria | `/proc/pressure/memory` |
| Uso de CPU | `/proc/stat`, diferencia entre dos lecturas |
| Frecuencia, núcleos e hilos | `/sys/devices/system/cpu/cpu*/cpufreq` y `topology` |
| Procesos | `/proc/PID/stat` (nombre, padre, tiempo de CPU, inicio), `statm` (memoria), `cgroup` (unidad), dueño del directorio |
| Temperaturas | `/sys/class/hwmon/*/temp*_input`; la CPU de la barra es `Package id 0` de coretemp |
| Ventiladores de la placa | `/sys/class/hwmon/*/fan*_input` |
| GPU | NVML: nombre, uso, temperatura, memoria, frecuencias, potencia, codificador, decodificador, ventiladores y núcleos |
| GPU por proceso | NVML: `nvmlDeviceGetProcessUtilization` y los procesos de cómputo y gráficos |
| Consumo de Kortex | `/proc/self/smaps_rollup` (PSS) y `/proc/self/stat` |
| Pantalla bloqueada | señal `ActiveChanged` de `org.freedesktop.ScreenSaver` |

### macOS

Todas se leen sin permisos de administrador; escribir el modo y el objetivo de los ventiladores es lo único que pide root.

| Dato | Fuente |
|---|---|
| RAM, caché | `host_statistics64` (`HOST_VM_INFO64`) |
| Swap | `vm.swapusage` |
| Presión de memoria | `kern.memorystatus_vm_pressure_level` y evento de presión de memoria del sistema |
| Consumo por proceso (RAM, CPU) | `top` para la memoria real y diferencia de tiempo de CPU de `ps` para el porcentaje; ambos vienen con macOS y ven todos los procesos |
| Hora de inicio de un proceso | `proc_pidinfo` (`PROC_PIDTBSDINFO`) |
| Uso de GPU, memoria de GPU | `IOAccelerator` → `PerformanceStatistics` |
| Nombre de la GPU, máximo de memoria para GPU | Metal: `name` y `recommendedMaxWorkingSetSize`, leídos una vez |
| GPU por proceso | `AppUsage.accumulatedGPUTime` de cada `AGXDeviceUserClient` del IORegistry, con el proceso dueño en `IOUserClientCreator` |
| Frecuencia y consumo de GPU | IOReport: residencia por estado del canal `GPUPH` del grupo "GPU Stats" y nanojulios del canal `GPU Energy` del grupo "Energy Model" |
| Frecuencia máxima de GPU | Tabla `voltage-states` de `pmgr` en IORegistry |
| Temperaturas | Claves del SMC: `Tp*` CPU, `Tg*` GPU, `Tm*` memoria, `TN*` SSD, `TB*` batería |
| Ventiladores | Claves del SMC: `FNum` cuántos hay, `F{n}Ac` RPM, `F{n}Mn` · `F{n}Mx` mínimo y máximo, `F{n}md` modo y `F{n}Tg` objetivo |
| Energía por proceso | `proc_pid_rusage` → `ri_energy_nj`, por diferencia entre dos lecturas (solo procesos del usuario) |
| Batería y adaptador | `AppleSmartBattery` en IORegistry |
| Modo de energía | Configuración de energía del sistema (`powermode`) |
| Consumo de Kortex | `task_info` del propio proceso y de los subprocesos que lanza (`top`): `phys_footprint` y tiempo de CPU |

Apple no documenta el significado de las claves del SMC. La asignación por zona se validó con la CPU al máximo durante 45 s: CPU 61,8 → 87,5 °C, memoria 60,1 → 84,7 °C, GPU 53,3 → 72,0 °C, SSD 40,0 → 42,0 °C y batería 33,4 → 33,4 °C. Las tres zonas del chip suben juntas y las dos de fuera apenas se mueven. El equipo expone 23 sensores de CPU y 42 de GPU, y el SMC responde despacio: cada clave cuesta 0,17 ms, más que todas las demás métricas juntas. Por eso cada lectura refresca doce sensores por turno, rotando sobre la lista, y muestra el máximo de los valores guardados; la lista entera se renueva cada tres lecturas. Entre los sensores de GPU la diferencia es de un grado, así que basta con ocho repartidos; entre los de CPU llega a ocho grados, y se leen todos.
