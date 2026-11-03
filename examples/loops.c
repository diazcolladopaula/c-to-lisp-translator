int total ;

main () {
    int i ;
    total = 0 ;
    for (i = 1 ; i <= 5 ; INC(i)) {
        total = total + i ;
    }
    while (total > 10) {
        DEC(total) ;
    }
    printf("%d", total) ;
}
