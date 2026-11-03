# C-to-Lisp Translator

[Leer en español](README.es.md)

A syntax-directed translator, written with **Bison (Yacc) and C**, that converts programs in a subset of C into Lisp prefix notation. The output can be evaluated directly by a **Common Lisp** interpreter.

> University project for the *Language Processors* course (Universidad Carlos III de Madrid, 2025-2026), developed as a team of two.

```
C source  →  [hand-written lexer + Bison grammar]  →  Lisp prefix notation  →  Common Lisp interpreter
```

## Example

**Input (C)**
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

**Output (Lisp)**
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

The generated program always ends with `(main)`, which starts execution when the file is evaluated. More examples are in [`examples/`](examples/).

## Supported language

- **Variables:** global and local `int` declarations, with or without a constant initializer
- **Expressions:** `+ - * / %`, comparisons `== != < <= > >=`, logical `&& || !`, unary `+`/`-`, parentheses, with C precedence and associativity
- **Control flow:** `if` / `if-else` (braces required, which avoids the dangling-else ambiguity), `while`, and a canonical `for` loop whose increment is written `INC(x)` or `DEC(x)`
- **Functions:** user functions with zero or one `int` parameter, calls as statements or inside expressions, and `return` translated to `(return-from <function> <expr>)`
- **Output:** `puts("text")` becomes `(print "text")`; `printf("fmt", e1, e2, ...)` becomes one `(princ ...)` per argument (the format string itself is discarded)
- **Arrays:** `v[i]` is translated to `(aref v i)` (see limitations)

## Build and run

Requires `bison` and `gcc`.

```bash
make                                   # bison -d c2lisp.y && gcc -o c2lisp c2lisp.tab.c
./c2lisp < examples/ifelse.c > out.lisp
make test                              # translate every program in examples/
```

To check the result, evaluate the generated file with any Common Lisp implementation (for example `sbcl --script out.lisp`).

## How it works

- **Grammar structure:** the axiom `programa` requires global declarations first, followed by a list of functions (`main` included, in any order). Generated code ends with a call to `main`.
- **Explicit attributes:** every grammar symbol carries a `t_attr` struct with `value` (numeric constants), `code` (generated Lisp text) and `node` (reserved for a future AST).
- **Scope handling:** `setq` in Lisp always creates a global variable, so the translator keeps a per-function table of local variables and renames them to `function_variable` (for example `f` inside `fact` becomes `fact_f`). Declarations use `setq` and later assignments to locals use `setf`. This is resolved entirely at translation time.
- **Conflict-free grammar:** statements ending in `;` and control structures (which do not) have separate productions, and `main` and user functions have their own statement lists. Bison reports no shift/reduce conflicts.
- **Precedence:** declared with `%left` / `%right` following the [C operator precedence table](https://en.cppreference.com/w/c/language/operator_precedence).
- **Lexer:** written by hand in C (no Flex). It lowercases identifiers, skips `#` lines and `//` comments, and copies lines starting with `//@` straight to the output.

## Known limitations

- **Arrays are incomplete.** `v[i]` is parsed for reading and writing, but there is no array declaration rule (`int v[10];`), so `v` is always declared as a scalar and the generated `aref` would fail at run time. Adding a rule that emits `(setq v (make-array N))` would complete it.
- Only the `int` type is supported (no `char`, `float`, structs or pointers).
- Functions take at most one `int` parameter.
- Initializers must be integer constants (`int x = 3;`, not `int x = y + 1;`).
- Identifiers are case-insensitive because the lexer lowercases them.
- Code fragments are built in fixed-size buffers, so very large expressions or blocks are not supported.

## Repository layout

```
.
├── c2lisp.y        # Bison grammar, lexer and translator
├── Makefile
├── examples/       # Sample C programs (if/else, loops, functions)
├── LICENSE
├── README.md
└── README.es.md
```

## License

MIT, see [LICENSE](LICENSE).
