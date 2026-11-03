/*
 * c2lisp.y - Translator from a subset of C to Lisp prefix notation.
 *
 * Build:  bison -d c2lisp.y && gcc -o c2lisp c2lisp.tab.c
 * Usage:  ./c2lisp < program.c > program.lisp
 */

%{

#include <stdio.h>
#include <ctype.h>            // tolower
#include <string.h>           // string functions
#include <stdlib.h>           // exit ()

#define FF fflush(stdout);    // force immediate output

int yylex () ;
int yyerror (char *) ;        
char *gen_code (char *) ;
char *int_to_string (int) ;
char *char_to_string (char) ;

char temp [8192] ;

// AST node structure (reserved for future use)

typedef struct ASTnode t_node ;

struct ASTnode {
    char *op ;
    int type ;      // leaf, unary or binary node
    t_node *left ;
    t_node *right ;
} ;


// Explicit semantic attributes

typedef struct s_attr {
    int value ;    // numeric value of a NUMBER
    char *code ;   // identifier names and generated Lisp code
    t_node *node ; // reserved for a future AST representation
} t_attr ;

#define YYSTYPE t_attr

// Name of the function being translated (used for local names and return-from)
char current_function [256] = "main" ;

// Local variables of the current function
#define MAX_LOCAL_VARS 256
char local_vars [MAX_LOCAL_VARS][256] ;
int n_local_vars = 0 ;

// Returns 1 if name is a local variable of the current function
int is_local_var (char *name) {
    int i ;
    for (i = 0; i < n_local_vars; i++) {
        if (strcmp(local_vars[i], name) == 0) return 1 ;
    }
    return 0 ;
}

// Registers a local variable
void register_local_var (char *name) {
    if (!is_local_var(name) && n_local_vars < MAX_LOCAL_VARS) {
        strcpy(local_vars[n_local_vars++], name) ;
    }
}

// Clears the local variable table (on entering a new function)
void clear_local_vars () {
    n_local_vars = 0 ;
}

// Builds the prefixed name of a local variable: function_var
char *local_name (char *func, char *var) {
    static char buf [512] ;
    sprintf(buf, "%s_%s", func, var) ;
    return buf ;
}

%}

// Tokens

%token NUMBER        
%token IDENTIF       // identifier
%token INTEGER       // int type
%token STRING
%token MAIN          // main function
%token WHILE         // while loop
%token IF            // if statement
%token ELSE          // else branch
%token PUTS          // puts (string output)
%token PRINTF        // printf (formatted output)
%token RETURN        // return
%token INC           // INC(x) - increment
%token DEC           // DEC(x) - decrement
%token FOR           // for loop

// Two-character comparison and logical operators
%token EQ            // ==
%token NEQ           // !=
%token LEQ           // <=
%token GEQ           // >=
%token AND           // &&
%token OR            // ||

// Precedence and associativity (lowest to highest)
%left OR                      
%left AND                     // &&
%precedence '!'               // unary not
%left EQ NEQ                  // == !=
%left '<' '>' LEQ GEQ         // relational comparisons
%left '+' '-'                 // addition and subtraction
%left '*' '/' '%'             // multiplication, division, modulo
%precedence UNARY_SIGN        // unary sign, used through %prec

%%

// Global declarations, then functions
axioma:       programa                   { printf ("%s\n", $1.code) ; }
            ;

programa:     lista_declaraciones lista_funciones {
                                           sprintf(temp, "%s\n%s\n(main)", $1.code, $2.code) ;
                                           $$.code = gen_code(temp) ; 
                                         }
            ;

// --- 1. GLOBAL VARIABLES ---
lista_declaraciones: lista_declaraciones declaracion {
                                           if (strlen($1.code) == 0) sprintf(temp, "%s", $2.code) ;
                                           else sprintf(temp, "%s\n%s", $1.code, $2.code) ;
                                           $$.code = gen_code(temp) ; 
                                         }
            | /* epsilon */              { $$.code = gen_code("") ; }
            ;

declaracion:  INTEGER lista_variables ';' { $$.code = $2.code ; }
            ;

lista_variables: lista_variables ',' variable_init {
                                           sprintf(temp, "%s\n%s", $1.code, $3.code) ;
                                           $$.code = gen_code(temp) ; 
                                         }
            | variable_init              { $$.code = $1.code ; }
            ;

variable_init: IDENTIF                   { sprintf(temp, "(setq %s 0)", $1.code) ;
                                           $$.code = gen_code(temp) ; }
            | IDENTIF '=' NUMBER         { sprintf(temp, "(setq %s %d)", $1.code, $3.value) ;
                                           $$.code = gen_code(temp) ; }
            ;

// --- 2. FUNCTION LIST ---
lista_funciones: lista_funciones funcion  {
                                           sprintf(temp, "%s\n%s", $1.code, $2.code) ;
                                           $$.code = gen_code(temp) ;
                                         }
            | funcion                    { $$.code = $1.code ; }
            ;

// A function is either main or a user-defined function
funcion:      funcion_main               { $$.code = $1.code ; }
            | funcion_usuario            { $$.code = $1.code ; }
            ;

// --- 3. MAIN FUNCTION ---
funcion_main: MAIN '(' ')' '{'
                {
                    // Reset the local table on entering main
                    strcpy(current_function, "main") ;
                    clear_local_vars() ;
                }
              lista_sentencias_main '}' {
                                           sprintf(temp, "(defun main ()\n%s\n)", $6.code) ;
                                           $$.code = gen_code(temp) ; 
                                         }
            ;

// --- 4. USER FUNCTIONS ---
// No parameters: name () { ... }
funcion_usuario: IDENTIF '(' ')' '{'
                {
                    // Save the function name and reset the local table
                    strcpy(current_function, $1.code) ;
                    clear_local_vars() ;
                }
              lista_sentencias_funcion '}' {
                                           sprintf(temp, "(defun %s ()\n%s\n)", $1.code, $6.code) ;
                                           $$.code = gen_code(temp) ;
                                         }
            // One parameter: name (int param) { ... }
            | IDENTIF '(' INTEGER IDENTIF ')' '{'
                {
                    strcpy(current_function, $1.code) ;
                    clear_local_vars() ;
                    // The parameter is a Lisp argument, so it is not prefixed
                }
              lista_sentencias_funcion '}' {
                                           sprintf(temp, "(defun %s (%s)\n%s\n)", $1.code, $4.code, $8.code) ;
                                           $$.code = gen_code(temp) ;
                                         }
            ;

// --- STATEMENTS INSIDE main ---
// Local declarations may be mixed with statements
lista_sentencias_main: lista_sentencias_main sentencia_main {
                                           if (strlen($1.code) == 0) sprintf(temp, "  %s", $2.code) ;
                                           else sprintf(temp, "%s\n  %s", $1.code, $2.code) ;
                                           $$.code = gen_code(temp) ;
                                         }
            | lista_sentencias_main decl_local_main {
                                           if (strlen($1.code) == 0) sprintf(temp, "  %s", $2.code) ;
                                           else sprintf(temp, "%s\n  %s", $1.code, $2.code) ;
                                           $$.code = gen_code(temp) ;
                                         }
            | /* epsilon */              { $$.code = gen_code("") ; }
            ;

sentencia_main: sentencia ';'            { $$.code = $1.code ; }
            | estructura_control         { $$.code = $1.code ; }
            ;

// Local declaration inside main (setq with function-name prefix)
decl_local_main: INTEGER lista_variables_locales ';' { $$.code = $2.code ; }
            ;

lista_variables_locales: lista_variables_locales ',' variable_local {
                                           sprintf(temp, "%s\n  %s", $1.code, $3.code) ;
                                           $$.code = gen_code(temp) ;
                                         }
            | variable_local             { $$.code = $1.code ; }
            ;

variable_local: IDENTIF                  {
                                           register_local_var($1.code) ;
                                           sprintf(temp, "(setq %s 0)", local_name(current_function, $1.code)) ;
                                           $$.code = gen_code(temp) ;
                                         }
            | IDENTIF '=' NUMBER         {
                                           register_local_var($1.code) ;
                                           sprintf(temp, "(setq %s %d)", local_name(current_function, $1.code), $3.value) ;
                                           $$.code = gen_code(temp) ;
                                         }
            ;

// --- STATEMENTS INSIDE USER FUNCTIONS ---
lista_sentencias_funcion: lista_sentencias_funcion sentencia_func {
                                           if (strlen($1.code) == 0) sprintf(temp, "  %s", $2.code) ;
                                           else sprintf(temp, "%s\n  %s", $1.code, $2.code) ;
                                           $$.code = gen_code(temp) ;
                                         }
            | lista_sentencias_funcion decl_local_func {
                                           if (strlen($1.code) == 0) sprintf(temp, "  %s", $2.code) ;
                                           else sprintf(temp, "%s\n  %s", $1.code, $2.code) ;
                                           $$.code = gen_code(temp) ;
                                         }
            | /* epsilon */              { $$.code = gen_code("") ; }
            ;

sentencia_func: sentencia ';'            { $$.code = $1.code ; }
            | sentencia_return ';'       { $$.code = $1.code ; }
            | estructura_control         { $$.code = $1.code ; }
            ;

// Local declaration inside a user function
decl_local_func: INTEGER lista_variables_locales ';' { $$.code = $2.code ; }
            ;

// --- GENERIC STATEMENT LIST (if/while/for blocks) ---
lista_sentencias: lista_sentencias sentencia_bloque {
                                           if (strlen($1.code) == 0) sprintf(temp, "    %s", $2.code) ;
                                           else sprintf(temp, "%s\n    %s", $1.code, $2.code) ;
                                           $$.code = gen_code(temp) ;
                                         }
            | /* epsilon */              { $$.code = gen_code("") ; }
            ;

sentencia_bloque: sentencia ';'          { $$.code = $1.code ; }
            | sentencia_return ';'       { $$.code = $1.code ; }
            | estructura_control         { $$.code = $1.code ; }
            ;

// --- SIMPLE STATEMENTS ---
sentencia:    IDENTIF '=' expresion      {
                                           // Assignment: setf for local variables, setq otherwise
                                           if (is_local_var($1.code)) {
                                               sprintf(temp, "(setf %s %s)", local_name(current_function, $1.code), $3.code) ;
                                           } else {
                                               sprintf(temp, "(setq %s %s)", $1.code, $3.code) ;
                                           }
                                           $$.code = gen_code(temp) ;
                                         }
            // Array element assignment: v[i] = expr
            | IDENTIF '[' expresion ']' '=' expresion {
                                           if (is_local_var($1.code)) {
                                               sprintf(temp, "(setf (aref %s %s) %s)", local_name(current_function, $1.code), $3.code, $6.code) ;
                                           } else {
                                               sprintf(temp, "(setf (aref %s %s) %s)", $1.code, $3.code, $6.code) ;
                                           }
                                           $$.code = gen_code(temp) ;
                                         }
            // puts
            | PUTS '(' STRING ')'        { sprintf(temp, "(print \"%s\")", $3.code) ;
                                           $$.code = gen_code(temp) ; }
            // printf with a format string and arguments
            | PRINTF '(' STRING ',' printf_args ')' {
                                           $$.code = $5.code ;
                                         }
            // Function call as a statement
            | IDENTIF '(' ')'            { sprintf(temp, "(%s)", $1.code) ;
                                           $$.code = gen_code(temp) ; }
            | IDENTIF '(' expresion ')'  { sprintf(temp, "(%s %s)", $1.code, $3.code) ;
                                           $$.code = gen_code(temp) ; }
            | INC '(' IDENTIF ')'        {
                                           if (is_local_var($3.code)) {
                                               sprintf(temp, "(setq %s (+ %s 1))", local_name(current_function, $3.code), local_name(current_function, $3.code)) ;
                                           } else {
                                               sprintf(temp, "(setq %s (+ %s 1))", $3.code, $3.code) ;
                                           }
                                           $$.code = gen_code(temp) ;
                                         }
            | DEC '(' IDENTIF ')'        {
                                           if (is_local_var($3.code)) {
                                               sprintf(temp, "(setq %s (- %s 1))", local_name(current_function, $3.code), local_name(current_function, $3.code)) ;
                                           } else {
                                               sprintf(temp, "(setq %s (- %s 1))", $3.code, $3.code) ;
                                           }
                                           $$.code = gen_code(temp) ;
                                         }
            ;

// return statement
sentencia_return: RETURN expresion       {
                                           sprintf(temp, "(return-from %s %s)", current_function, $2.code) ;
                                           $$.code = gen_code(temp) ;
                                         }
            ;

// printf arguments: one or more comma-separated elements.
// Each element is an expression or a string and becomes its own (princ ...)
printf_args:  printf_args ',' printf_elem {
                                           sprintf(temp, "%s\n    %s", $1.code, $3.code) ;
                                           $$.code = gen_code(temp) ;
                                         }
            | printf_elem                { $$.code = $1.code ; }
            ;

printf_elem:  expresion                  { sprintf(temp, "(princ %s)", $1.code) ;
                                           $$.code = gen_code(temp) ; }
            | STRING                     { sprintf(temp, "(princ \"%s\")", $1.code) ;
                                           $$.code = gen_code(temp) ; }
            ;

// --- CONTROL STRUCTURES ---
estructura_control:
            // while ( expr ) { statements }
              WHILE '(' expresion ')' '{' lista_sentencias '}' {
                                           if (strlen($6.code) == 0) {
                                               sprintf(temp, "(loop while %s do\n    )", $3.code) ;
                                           } else {
                                               sprintf(temp, "(loop while %s do\n%s\n  )", $3.code, $6.code) ;
                                           }
                                           $$.code = gen_code(temp) ;
                                         }
            // if ( expr ) { statements }
            | IF '(' expresion ')' '{' lista_sentencias '}' {
                                           char *cuerpo = $6.code ;
                                           if (strlen(cuerpo) == 0) {
                                               sprintf(temp, "(if %s\n    nil)", $3.code) ;
                                           } else {
                                               // progn is needed when the body has more than one line
                                               int count = 0 ; char *p = cuerpo ;
                                               while (*p) { if (*p == '\n') count++ ; p++ ; }
                                               if (count > 0) {
                                                   sprintf(temp, "(if %s\n  (progn\n%s\n  ))", $3.code, cuerpo) ;
                                               } else {
                                                   sprintf(temp, "(if %s\n%s)", $3.code, cuerpo) ;
                                               }
                                           }
                                           $$.code = gen_code(temp) ;
                                         }
            // if ( expr ) { ... } else { ... }
            | IF '(' expresion ')' '{' lista_sentencias '}' ELSE '{' lista_sentencias '}' {
                                           char *then_code = $6.code ;
                                           char *else_code = $10.code ;
                                           char then_str[2048], else_str[2048] ;
                                           int then_lines = 0, else_lines = 0 ;
                                           char *p ;
                                           for (p = then_code; *p; p++) if (*p == '\n') then_lines++ ;
                                           for (p = else_code; *p; p++) if (*p == '\n') else_lines++ ;
                                           if (then_lines > 0) {
                                               sprintf(then_str, "(progn\n%s\n  )", then_code) ;
                                           } else {
                                               sprintf(then_str, "%s", then_code) ;
                                           }
                                           if (else_lines > 0) {
                                               sprintf(else_str, "(progn\n%s\n  )", else_code) ;
                                           } else {
                                               sprintf(else_str, "%s", else_code) ;
                                           }
                                           sprintf(temp, "(if %s\n  %s\n  %s)", $3.code, then_str, else_str) ;
                                           $$.code = gen_code(temp) ;
                                         }
            // canonical for: for ( id = expr ; expr ; INC/DEC(id) ) { statements }
            | FOR '(' IDENTIF '=' expresion ';' expresion ';' sentencia_for_inc ')' '{' lista_sentencias '}' {
                                           char *var_name ;
                                           if (is_local_var($3.code)) {
                                               var_name = local_name(current_function, $3.code) ;
                                           } else {
                                               var_name = $3.code ;
                                           }
                                           if (strlen($12.code) == 0) {
                                               sprintf(temp, "(setq %s %s)\n  (loop while %s do\n    %s\n  )",
                                                   var_name, $5.code, $7.code, $9.code) ;
                                           } else {
                                               sprintf(temp, "(setq %s %s)\n  (loop while %s do\n%s\n    %s\n  )",
                                                   var_name, $5.code, $7.code, $12.code, $9.code) ;
                                           }
                                           $$.code = gen_code(temp) ;
                                         }
            ;

// Increment/decrement in the for header
sentencia_for_inc: INC '(' IDENTIF ')' {
                                           if (is_local_var($3.code)) {
                                               sprintf(temp, "(setq %s (+ %s 1))", local_name(current_function, $3.code), local_name(current_function, $3.code)) ;
                                           } else {
                                               sprintf(temp, "(setq %s (+ %s 1))", $3.code, $3.code) ;
                                           }
                                           $$.code = gen_code(temp) ;
                                         }
            | DEC '(' IDENTIF ')' {
                                           if (is_local_var($3.code)) {
                                               sprintf(temp, "(setq %s (- %s 1))", local_name(current_function, $3.code), local_name(current_function, $3.code)) ;
                                           } else {
                                               sprintf(temp, "(setq %s (- %s 1))", $3.code, $3.code) ;
                                           }
                                           $$.code = gen_code(temp) ;
                                         }
            ;

// --- EXPRESSIONS ---
expresion:      termino                  { $$.code = $1.code ; }
            // Arithmetic operators
            |   expresion '+' expresion  { sprintf (temp, "(+ %s %s)", $1.code, $3.code) ;
                                           $$.code = gen_code (temp) ; }
            |   expresion '-' expresion  { sprintf (temp, "(- %s %s)", $1.code, $3.code) ;
                                           $$.code = gen_code (temp) ; }
            |   expresion '*' expresion  { sprintf (temp, "(* %s %s)", $1.code, $3.code) ;
                                           $$.code = gen_code (temp) ; }
            |   expresion '/' expresion  { sprintf (temp, "(/ %s %s)", $1.code, $3.code) ;
                                           $$.code = gen_code (temp) ; }
            |   expresion '%' expresion  { sprintf (temp, "(mod %s %s)", $1.code, $3.code) ;
                                           $$.code = gen_code (temp) ; }
            // Comparison operators
            |   expresion EQ  expresion  { sprintf (temp, "(= %s %s)", $1.code, $3.code) ;
                                           $$.code = gen_code (temp) ; }
            |   expresion NEQ expresion  { sprintf (temp, "(/= %s %s)", $1.code, $3.code) ;
                                           $$.code = gen_code (temp) ; }
            |   expresion '<' expresion  { sprintf (temp, "(< %s %s)", $1.code, $3.code) ;
                                           $$.code = gen_code (temp) ; }
            |   expresion LEQ expresion  { sprintf (temp, "(<= %s %s)", $1.code, $3.code) ;
                                           $$.code = gen_code (temp) ; }
            |   expresion '>' expresion  { sprintf (temp, "(> %s %s)", $1.code, $3.code) ;
                                           $$.code = gen_code (temp) ; }
            |   expresion GEQ expresion  { sprintf (temp, "(>= %s %s)", $1.code, $3.code) ;
                                           $$.code = gen_code (temp) ; }
            // Logical operators
            |   expresion AND expresion  { sprintf (temp, "(and %s %s)", $1.code, $3.code) ;
                                           $$.code = gen_code (temp) ; }
            |   expresion OR  expresion  { sprintf (temp, "(or %s %s)", $1.code, $3.code) ;
                                           $$.code = gen_code (temp) ; }
            |   '!' expresion            { sprintf (temp, "(not %s)", $2.code) ;
                                           $$.code = gen_code (temp) ; }
            ;

termino:        operando                           { $$.code = $1.code ; }                          
            |   '+' operando %prec UNARY_SIGN      { $$.code = $2.code ; }
            |   '-' operando %prec UNARY_SIGN      { sprintf (temp, "(- %s)", $2.code) ;
                                                     $$.code = gen_code (temp) ; }    
            ;

operando:       IDENTIF                  {
                                           // Local variables use their prefixed name
                                           if (is_local_var($1.code)) {
                                               sprintf(temp, "%s", local_name(current_function, $1.code)) ;
                                           } else {
                                               sprintf(temp, "%s", $1.code) ;
                                           }
                                           $$.code = gen_code(temp) ;
                                         }
            |   NUMBER                   { sprintf (temp, "%d", $1.value) ;
                                           $$.code = gen_code (temp) ; }
            |   '(' expresion ')'        { $$.code = $2.code ; }
            // Function call in an expression (no arguments)
            |   IDENTIF '(' ')'          { sprintf(temp, "(%s)", $1.code) ;
                                           $$.code = gen_code(temp) ; }
            // Function call in an expression (one argument)
            |   IDENTIF '(' expresion ')' { sprintf(temp, "(%s %s)", $1.code, $3.code) ;
                                           $$.code = gen_code(temp) ; }
            // Array element access: v[i]
            |   IDENTIF '[' expresion ']' {
                                           char *vname ;
                                           if (is_local_var($1.code)) {
                                               vname = local_name(current_function, $1.code) ;
                                           } else {
                                               vname = $1.code ;
                                           }
                                           sprintf(temp, "(aref %s %s)", vname, $3.code) ;
                                           $$.code = gen_code(temp) ;
                                         }
            ;

%%

int n_line = 1 ;

int yyerror (char *mensaje)
{
    fprintf (stderr, "%s at line %d\n", mensaje, n_line) ;
    printf ("\n") ;
    return 0;
}

char *int_to_string (int n)
{
    sprintf (temp, "%d", n) ;
    return gen_code (temp) ;
}

char *char_to_string (char c)
{
    sprintf (temp, "%c", c) ;
    return gen_code (temp) ;
}

char *my_malloc (int nbytes)       // allocates n bytes of dynamic memory
{
    char *p ;
    static long int nb = 0;        // total memory requested
    static int nv = 0 ;            // (bytes and number of calls)

    p = malloc (nbytes) ;
    if (p == NULL) {
        fprintf (stderr, "Out of memory: cannot allocate %d more bytes\n", nbytes) ;
        fprintf (stderr, "Allocated %ld bytes in %d calls\n", nb, nv) ;
        exit (0) ;
    }
    nb += (long) nbytes ;
    nv++ ;

    return p ;
}


/***************************************************************************/
/***************************** Reserved words ******************************/
/***************************************************************************/

typedef struct s_keyword { // reserved word entry
    char *name ;
    int token ;
} t_keyword ;

t_keyword keywords [] = { // reserved words and their tokens
    "main",        MAIN,
    "int",         INTEGER,
    "while",       WHILE,
    "if",          IF,
    "else",        ELSE,
    "puts",        PUTS,
    "printf",      PRINTF,
    "return",      RETURN,
    "inc",         INC,
    "dec",         DEC,
    "for",         FOR,
    // Two-character operators
    "==",          EQ,
    "!=",          NEQ,
    "<=",          LEQ,
    ">=",          GEQ,
    "&&",          AND,
    "||",          OR,
    NULL,          0               // end of table
} ;

t_keyword *search_keyword (char *symbol_name)
{                                  // Looks symbol_name up in the table and
                                   // returns its entry, or NULL
    int i ;
    t_keyword *sim ;

    i = 0 ;
    sim = keywords ;
    while (sim [i].name != NULL) {
        if (strcmp (sim [i].name, symbol_name) == 0) {
            return &(sim [i]) ;
        }
        i++ ;
    }

    return NULL ;
}

 
/***************************************************************************/
/**************************** Lexical analyzer *****************************/
/***************************************************************************/

char *gen_code (char *name)     // copies the argument into
{                                      // a dynamically allocated string
    char *p ;
    int l ;
    
    l = strlen (name)+1 ;
    p = (char *) my_malloc (l) ;
    strcpy (p, name) ;
    
    return p ;
}


int yylex ()
{
    int i ;
    unsigned char c ;
    unsigned char cc ;
    char two_char_ops [] = "!<=|>%&/+-*" ;
    char temp_str [256] ;
    t_keyword *symbol ;

    do {
        c = getchar () ;

        if (c == '#') {    // Skip preprocessor lines (#define, #include)
            do {
                c = getchar () ;
            } while (c != '\n') ;
        }

        if (c == '/') {    // A / may start a comment
            cc = getchar () ;
            if (cc != '/') {   // not a comment: put the character back
                ungetc (cc, stdin) ;
            } else {
                c = getchar () ;
                if (c == '@') {    // //@ sequence: copy the line to the output as is
                    do {                                c = getchar () ;
                        putchar (c) ;
                    } while (c != '\n') ;
                } else {        // regular comment: skip the line
                    while (c != '\n') {
                        c = getchar () ;
                    }
                }
            }
        } else if (c == '\\') c = getchar () ;
        
        if (c == '\n')
            n_line++ ;

    } while (c == ' ' || c == '\n' || c == 10 || c == 13 || c == '\t') ;

    if (c == '\"') {
        i = 0 ;
        do {
            c = getchar () ;
            temp_str [i++] = c ;
        } while (c != '\"' && i < 255) ;
        if (i == 256) {
            printf ("WARNING: string longer than 255 characters at line %d\n", n_line) ;
        }
        temp_str [--i] = '\0' ;
        yylval.code = gen_code (temp_str) ;
        return (STRING) ;
    }

    if (c == '.' || (c >= '0' && c <= '9')) {
        ungetc (c, stdin) ;
        scanf ("%d", &yylval.value) ;
        return NUMBER ;
    }

    if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) {
        i = 0 ;
        while (((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
            (c >= '0' && c <= '9') || c == '_') && i < 255) {
            temp_str [i++] = tolower (c) ;
            c = getchar () ;
        }
        temp_str [i] = '\0' ;
        ungetc (c, stdin) ;

        yylval.code = gen_code (temp_str) ;
        symbol = search_keyword (yylval.code) ;
        if (symbol == NULL) {    // not a reserved word: identifier
            return (IDENTIF) ;
        } else {
            return (symbol->token) ;
        }
    }

    if (strchr (two_char_ops, c) != NULL) { // c may start a two-character operator
        cc = getchar () ;
        sprintf (temp_str, "%c%c", (char) c, (char) cc) ;
        symbol = search_keyword (temp_str) ;
        if (symbol == NULL) {
            ungetc (cc, stdin) ;
            yylval.code = NULL ;
            return (c) ;
        } else {
            yylval.code = gen_code (temp_str) ; 
            return (symbol->token) ;
        }
    }

    if (c == EOF || c == 255 || c == 26) {
        return (0) ;
    }

    return c ;
}


int main ()
{
    yyparse () ;
    return 0;
}
