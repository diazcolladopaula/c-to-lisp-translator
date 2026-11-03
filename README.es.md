# Traductor de C a Lisp

[Read in English](README.md)

Traductor dirigido por la sintaxis, escrito con **Bison (Yacc) y C**, que convierte programas de un subconjunto de C a notación prefija de Lisp. La salida se puede evaluar directamente en un intérprete de **Common Lisp**.

> Proyecto de la asignatura *Procesadores del Lenguaje* (Universidad Carlos III de Madrid, 2025-2026), realizado en pareja.

```
código C  →  [lexer manual + gramática Bison]  →  notación prefija Lisp  →  intérprete Common Lisp
```

## Ejemplo

**Entrada (C)**
```c
int a = 1 ;
int b ;

main () {
    if (a == 0) {
        b = 123 ;
    } else {
        b = 456 ;
    }
    printf("%d", b) ;
}
```

**Salida (Lisp)**
```lisp
(setq a 1)
(setq b 0)
(defun main ()
  (if (= a 0)
      (setq b 123)
      (setq b 456))
  (princ b)
)
(main)
```

El programa generado siempre termina con `(main)`, que inicia la ejecución al evaluar el fichero. Hay más ejemplos en [`examples/`](examples/).

## Lenguaje soportado

- **Variables:** declaraciones `int` globales y locales, con o sin inicialización constante
- **Expresiones:** `+ - * / %`, comparaciones `== != < <= > >=`, lógicos `&& || !`, `+`/`-` unarios y paréntesis, con la precedencia y asociatividad de C
- **Control de flujo:** `if` / `if-else` (llaves obligatorias, lo que evita la ambigüedad del *dangling else*), `while` y un `for` canónico cuyo incremento se escribe `INC(x)` o `DEC(x)`
- **Funciones:** funciones de usuario con cero o un parámetro `int`, llamadas como sentencia o dentro de expresiones, y `return` traducido a `(return-from <función> <expr>)`
- **Salida:** `puts("texto")` genera `(print "texto")`; `printf("fmt", e1, e2, ...)` genera un `(princ ...)` por argumento (la cadena de formato se descarta)
- **Vectores:** `v[i]` se traduce a `(aref v i)` (ver limitaciones)

## Compilación y uso

Requiere `bison` y `gcc`.

```bash
make                                   # bison -d c2lisp.y && gcc -o c2lisp c2lisp.tab.c
./c2lisp < examples/ifelse.c > salida.lisp
make test                              # traduce todos los programas de examples/
```

Para comprobar el resultado, evalúa el fichero generado con cualquier implementación de Common Lisp (por ejemplo `sbcl --script salida.lisp`).

## Cómo funciona

- **Estructura de la gramática:** el axioma `programa` exige primero las declaraciones globales y después una lista de funciones (incluido `main`, en cualquier orden). El código generado termina con una llamada a `main`.
- **Atributos explícitos:** cada símbolo lleva una estructura `t_attr` con `value` (constantes numéricas), `code` (texto Lisp generado) y `node` (reservado para un futuro AST).
- **Gestión de ámbito:** en Lisp `setq` siempre crea una variable global, así que el traductor mantiene una tabla de variables locales por función y las renombra a `funcion_variable` (por ejemplo, `f` dentro de `fact` pasa a `fact_f`). Las declaraciones usan `setq` y las asignaciones posteriores a locales usan `setf`. Todo se resuelve en tiempo de traducción.
- **Gramática sin conflictos:** las sentencias terminadas en `;` y las estructuras de control (que no lo llevan) tienen producciones separadas, y `main` y las funciones de usuario tienen sus propias listas de sentencias. Bison no reporta conflictos shift/reduce.
- **Precedencias:** declaradas con `%left` / `%right` según la [tabla de precedencia de operadores de C](https://en.cppreference.com/w/c/language/operator_precedence).
- **Lexer:** escrito a mano en C (sin Flex). Pasa los identificadores a minúsculas, ignora las líneas con `#` y los comentarios `//`, y copia tal cual a la salida las líneas que empiezan por `//@`.

## Limitaciones conocidas

- **Vectores incompletos.** `v[i]` se reconoce en lectura y escritura, pero no hay regla de declaración de arrays (`int v[10];`), así que `v` se declara siempre como escalar y el `aref` generado fallaría al ejecutarse. Bastaría añadir una regla que genere `(setq v (make-array N))`.
- Solo se admite el tipo `int` (sin `char`, `float`, structs ni punteros).
- Las funciones admiten como máximo un parámetro `int`.
- Las inicializaciones deben ser constantes enteras (`int x = 3;`, no `int x = y + 1;`).
- Los identificadores no distinguen mayúsculas de minúsculas, porque el lexer los pasa a minúsculas.
- Los fragmentos de código se construyen en buffers de tamaño fijo, por lo que no se admiten expresiones o bloques muy grandes.

## Estructura del repositorio

```
.
├── c2lisp.y        # Gramática Bison, lexer y traductor
├── Makefile
├── examples/       # Programas C de ejemplo (if/else, bucles, funciones)
├── LICENSE
├── README.md
└── README.es.md
```

## Licencia

MIT, ver [LICENSE](LICENSE).
