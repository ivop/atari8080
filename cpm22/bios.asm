
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

; ibm-3740-noskew
;number_of_tracks = 77
;reserved_tracks = 2
;sectors_per_track = 26
;block_size = 1024
;dirents = 64

; atarihd
number_of_tracks = 455
reserved_tracks = 1
sectors_per_track = 18
block_size = 2048
dirents = 128

    if block_size = 1024
block_shift = 3
    elseif block_size = 2048
block_shift = 4
    elseif block_size = 4096
block_shift = 5
    elseif block_size = 8192
block_shift = 6
    elseif block_size = 16384
block_shift = 7
    endif

block_mask = (1 << block_shift) - 1

checksum_buffer_size = (dirents + 3) / 4
sectors = (number_of_tracks - reserved_tracks) * sectors_per_track
blocks_on_disk = sectors * 128 / block_size
allocation_vector_size = (blocks_on_disk + 7) / 8
directory_blocks = (dirents * 32) / block_size
allocation_bitmap = (0ffffh << (16 - directory_blocks)) & 0ffffh

    if directory_blocks = 0
        error "Directory must be at least one block in size!"
    endif
    if (dirents * 32) # block_size != 0
        error "Directory is not an even number of blocks in size!"
    endif

    if blocks_on_disk < 256
        if block_size = 1024
extent_mask = 000h              ; %00000000
        elseif block_size = 2048
extent_mask = 001h              ; %00000001
        elseif block_size = 4096
extent_mask = 003h              ; %00000011
        elseif block_size = 8192
extent_mask = 007h              ; %00000111
        elseif block_size = 16384
extent_mask = 00fh              ; %00001111
        endif
    else
        if block_size = 1024
            error "Cannot use a block size of 1024 on a large disk!"
        elseif block_size = 2048
extent_mask = 000h              ; %00000000
        elseif block_size = 4096
extent_mask = 001h              ; %00000001
        elseif block_size = 8192
extent_mask = 003h              ; %00000011
        elseif block_size = 16384
extent_mask = 007h              ; %00000111
        endif
    endif

dpblk:
    dw sectors_per_track
    db block_shift
    db block_mask
    db extent_mask
    dw blocks_on_disk - 1
    dw dirents - 1
    db (allocation_bitmap & 0ff00h)>>8
    db (allocation_bitmap & 000ffh)
    dw checksum_buffer_size
    dw reserved_tracks

dirbf:
    ds 128      ; can be the same for multiple disks
chk00:
    ds checksum_buffer_size
all00:
    ds allocation_vector_size
