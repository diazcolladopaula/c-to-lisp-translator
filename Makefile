all: c2lisp

c2lisp.tab.c: c2lisp.y
	bison -d c2lisp.y

c2lisp: c2lisp.tab.c
	gcc -o c2lisp c2lisp.tab.c

test: c2lisp
	@for f in examples/*.c; do echo "== $$f"; ./c2lisp < $$f; done

clean:
	rm -f c2lisp c2lisp.tab.c c2lisp.tab.h
