int n = 5, r ;

fact (int n2) {
    int f ;
    if (n2 <= 1) {
        return 1 ;
    }
    f = n2 * fact(n2 - 1) ;
    return f ;
}

suma () {
    int s = 0, i ;
    for (i = 1 ; i <= 10 ; INC(i)) {
        s = s + i ;
    }
    return s ;
}

main () {
    int k = 3 ;
    r = fact(n) ;
    printf("%d", r) ;
    printf("%d", suma()) ;
    while (k > 0) {
        puts("hola") ;
        DEC(k) ;
    }
    printf("%d %d", k, r % 7) ;
}
