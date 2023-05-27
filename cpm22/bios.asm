
    .cpu 8080

    org origin

; Trigger emulator to do stuff

boot:
    out 0
    ret
wboot:
    out 1
    ret
const:
    out 2
    ret
conin:
    out 3
    ret
conout:
    out 4
    ret
list:
    out 5
    ret
punch:
    out 6
    ret
reader:
    out 7
    ret
home:
    out 8
    ret
seldsk:
    out 9
    ret
settrk:
    out 10
    ret
setsec:
    out 11
    ret
setdma:
    out 12
    ret
read:
    out 13
    ret
write:
    out 14
    ret
listst:
    out 15
    ret
sectran:
    out 16
    ret

dpbase:
    dw trans
    db 0, 0, 0, 0, 0, 0
    dw dirbf
    dw dpblk
    dw chk00
    dw all00

; more disks here

; sector translate vector (not used)

trans:
    db 1, 2, 3,4, 5, 6, 7, 8, 9, 10, 11, 12, 13
    db 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26

; disk parameter block

dpblk:
    dw 26       ; sectors per track
    db 3        ; block shift factor
    db 7        ; block mask
    db 0        ; null mask (extent mask)
    dw 243-1    ; disk size in blocks - 1, excluding reserved tracks
    dw 64-1     ; directory entries - 1
    db 192      ; alloc hi
    db 0        ; alloc lo
    dw 16       ; check size 
    dw 2        ; track offset (reserved tracks)

dirbf:
    ds 128      ; can be the same for multiple disks
chk00:
    ds 16       ; check vector
all00:
    ds 31       ; allocation vector size bytes

