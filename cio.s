
CIOV    = $e456

ICHID   = $0340
ICDNO   = $0341
ICCOM   = $0342
ICSTA   = $0343
ICBAL   = $0344
ICBAH   = $0345
ICPTL   = $0346
ICPTH   = $0347
ICBLL   = $0348
ICBLH   = $0349
ICAX1   = $034a
ICAX2   = $034b
ICAX3   = $034c
ICAX4   = $034d
ICAX5   = $034e
ICAX6   = $034f

COPEN   = 3
CCLSE   = 12
CGTXT   = 5
CPTXT   = 9
CGBIN   = 7
CPBIN   = 11

EOL     = $9b

; -----------------------------------------------------------------------------

open .macro channel, aux1, aux2, filename
    jmp skip
fname
    .by ":filename" eol
skip
    ldx #:channel*16
    mva #:aux1 ICAX1,x
    mva #:aux2 ICAX2,x
    mva #COPEN ICCOM,x
    mwa #fname ICBAL,x
    jsr CIOV
    .mend

; -----------------------------------------------------------------------------

close .macro channel
    ldx #:channel*16
    mva #CCLSE ICCOM,x
    jsr CIOV
    .mend

; -----------------------------------------------------------------------------

print .macro channel, label
    ldx #:channel*16
    mva #CPTXT ICCOM,x
    mwa #:label ICBAL,x
    mwa #127 ICBLL,x
    jsr CIOV
    .mend

; -----------------------------------------------------------------------------

prints .macro channel, string
    jmp skip
str
    .by ":string" eol
skip
    print :channel, str
    .mend

printsn .macro channel, string
    jmp skip
str
    .by ":string"
skip
    bput :channel, skip-str, str
    .mend

; -----------------------------------------------------------------------------

input .macro channel, buffer
    ldx #:channel*16
    mva #CGTXT ICCOM,x
    mwa #:buffer ICBAL,x
    mwa #127 ICBLL,x
    jsr CIOV
    .mend

; -----------------------------------------------------------------------------

bget .macro channel, length, buffer
    ldx #:channel*16
    mva #CGBIN ICCOM,x
    mwa #:length ICBLL,x
    mwa #:buffer ICBAL,x
    jsr CIOV
    .mend

; -----------------------------------------------------------------------------

bput .macro channel, length, buffer
    ldx #:channel*16
    mva #CPBIN ICCOM,x
    mwa #:length ICBLL,x
    mwa #:buffer ICBAL,x
    jsr CIOV
    .mend

; -----------------------------------------------------------------------------

xio .macro command, channel, aux1, aux2, string
    jmp skip
str
    .by ":string" eol
skip
    ldx #:channel*16
    mva #:command ICCOM,x
    mva #:aux1 ICAX1,x
    mva #:aux2 ICAX2,x
    mwa #str ICBAL,x
    jsr CIOV
    .mend

; -----------------------------------------------------------------------------

