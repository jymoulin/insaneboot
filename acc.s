; acc.s - per-item accessory selection
;
; inside an .item block, lines starting with '@' configure the accessories
; loaded by the AES once the desktop starts (after insaneBOOT terminates):
;   @accdir <dir>      directory holding the accessories (default \ACCS)
;   @acc <NAME.ACC>    accessory to load (repeatable); no @acc = all of <dir>
;
; a resident GEMDOS (trap #1) hook redirects the AES enumeration "\*.ACC"
; to <dir>\*.ACC, filters the returned names against the @acc list and
; rewrites the following Fopen/Pexec(3,"NAME.ACC") to <dir>\NAME.ACC.
; the AES does Fopen + Pexec(3) per accessory, hence +2 per accepted name.
; later, a failing Fsfirst/Fopen of NAME.RSC (NAME = a loaded accessory,
; e.g. rsrc_load from the accessory) is retried as <dir>\NAME.RSC.
;
; layout: acc.s is included at the very start of the text segment. the
; resident part (hook + its variables) comes first, up to acc_res_end,
; so that only basepage + this block (+ the cookie jar, see resident.s)
; is kept by Ptermres. the init-only code follows.
;
; 68k only: the trap handler decodes the exception frame (68000 vs
; 68010+ via _longframe). on ColdFire the '@' lines are ignored.

ACCMAX=8		;max @acc names (TOS loads 6 accessories at most)
ACCNAMELEN=16		;bytes per name slot
ACCDIRLEN=64

	ifnd	_longframe
_longframe=$59e
	endc

		section	code
	ifnd	__mcoldfire__

;nested call of the previous GEMDOS vector from inside the handler
;(supervisor). parameters already pushed, result in d0, caller pops.
m_gemold	macro
		tst.w	_longframe.w
		beq	.sf\@
		move.w	#$84,-(sp)		;format/vector word (68010+)
.sf\@
		pea	.bk\@(pc)
		move.w	sr,-(sp)
		move.l	acc_oldvec(pc),a0
		jmp	(a0)
.bk\@
		endm

;---------------------------------------------------------------------
;GEMDOS hook. only d0-d2/a0-a2 are used on the pass-through path
;(scratch registers for GEMDOS anyway).
		dc.b	"XBRA"
		dc.b	"ISNB"
acc_oldvec	dc.l	0
acc_handler
		btst	#5,(sp)			;caller in supervisor mode ?
		beq.s	.usr
		lea	6(sp),a0		;parameters after the frame
		tst.w	_longframe.w
		beq.s	.got
		addq.l	#2,a0
		bra.s	.got
.usr		move.l	usp,a0			;parameters on the user stack
.got		move.w	(a0),d0
		cmp.w	#$4e,d0			;Fsfirst
		beq	acc_fsfirst
		cmp.w	#$4f,d0			;Fsnext
		beq	acc_fsnext
		cmp.w	#$3d,d0			;Fopen
		beq	acc_fopen
		cmp.w	#$4b,d0			;Pexec
		beq	acc_pexec
acc_pass
		move.l	acc_oldvec(pc),-(sp)
		rts

acc_fsfirst
		move.l	2(a0),a1		;pattern
		lea	s_staracc(pc),a2	;"\*.ACC" ?
.cmp		move.b	(a2)+,d1
		beq.s	.match
		cmp.b	(a1)+,d1
		bne	acc_fsrsc
		bra.s	.cmp
.match		tst.b	(a1)
		bne	acc_fsrsc
		clr.w	acc_count		;new enumeration
		clr.w	acc_loadedcnt
		move.w	#1,acc_enum
		move.w	6(a0),-(sp)		;attr
		pea	acc_pattern		;redirected pattern
		move.w	#$4e,-(sp)
		m_gemold
		addq.l	#8,sp
		bra.s	acc_filter

acc_fsnext
		tst.w	acc_enum
		beq	acc_pass
		move.w	#$4f,-(sp)
		m_gemold
		addq.l	#2,sp
acc_filter
;d0 = result of the nested Fsfirst/Fsnext: skip names not in the list
		tst.l	d0
		bne.s	.end
		move.w	#$2f,-(sp)		;Fgetdta
		m_gemold
		addq.l	#2,sp
		move.l	d0,a1
		lea	30(a1),a1		;filename in the DTA
		bsr	acc_inlist
		beq.s	.accept
		move.w	#$4f,-(sp)		;not wanted: next one
		m_gemold
		addq.l	#2,sp
		bra.s	acc_filter
.accept		addq.w	#2,acc_count		;Fopen + Pexec(3) to come
		move.w	acc_loadedcnt,d1	;remember the name (for .RSC)
		cmp.w	#ACCMAX,d1
		bge.s	.full
		lsl.w	#4,d1			;*ACCNAMELEN
		lea	acc_loaded,a2
		add.w	d1,a2
		moveq	#ACCNAMELEN-2,d1
.cpl		move.b	(a1)+,(a2)+
		dbeq	d1,.cpl
		clr.b	(a2)
		addq.w	#1,acc_loadedcnt
.full		moveq	#0,d0
		rte
.end		clr.w	acc_enum
		rte				;d0 = error, enumeration over

acc_fopen
		tst.w	acc_count
		beq	acc_forsc
		move.l	2(a0),a1
		bsr	acc_rewrite
		bne	acc_forsc
		move.l	#acc_path,2(a0)
		subq.w	#1,acc_count
		bra	acc_pass

acc_pexec
		tst.w	acc_count
		beq	acc_pass
		cmp.w	#3,2(a0)		;PE_LOAD only
		bne	acc_pass
		move.l	4(a0),a1
		bsr	acc_rewrite
		bne	acc_pass
		move.l	#acc_path,4(a0)
		tst.l	12(a0)			;no env: give PATH=<dir>
		bne.s	.env
		move.l	#acc_env,12(a0)
.env		subq.w	#1,acc_count
		bra	acc_pass

acc_fsrsc
;Fsfirst of a loaded accessory's NAME.RSC: original first, then <dir>
		move.l	2(a0),a1
		bsr	acc_rscpath
		bne	acc_pass
		move.l	a0,acc_parm
		move.w	6(a0),-(sp)		;attr
		move.l	2(a0),-(sp)		;original name
		move.w	#$4e,-(sp)
		m_gemold
		addq.l	#8,sp
		tst.l	d0
		bpl.s	.ok
		move.l	acc_parm,a0
		move.w	6(a0),-(sp)
		pea	acc_path		;<dir>\NAME.RSC
		move.w	#$4e,-(sp)
		m_gemold
		addq.l	#8,sp
.ok		rte

acc_forsc
;Fopen of a loaded accessory's NAME.RSC: original first, then <dir>
		move.l	2(a0),a1
		bsr	acc_rscpath
		bne	acc_pass
		move.l	a0,acc_parm
		move.w	6(a0),-(sp)		;mode
		move.l	2(a0),-(sp)
		move.w	#$3d,-(sp)
		m_gemold
		addq.l	#8,sp
		tst.l	d0
		bpl.s	.ok
		move.l	acc_parm,a0
		move.w	6(a0),-(sp)
		pea	acc_path
		move.w	#$3d,-(sp)
		m_gemold
		addq.l	#8,sp
.ok		rte

acc_rscpath
;in: a1=filename. out: Z=1 and acc_path = <dir>\<basename> when the
;basename is NAME.RSC (any case) and NAME.ACC was loaded. preserves regs.
		movem.l	d0-d2/a0-a3,-(sp)
		move.l	a1,a2			;basename
		move.l	a1,a3
.scan		move.b	(a3)+,d1
		beq.s	.scanned
		cmp.b	#'\',d1
		beq.s	.sep
		cmp.b	#':',d1
		bne.s	.scan
.sep		move.l	a3,a2
		bra.s	.scan
.scanned	move.l	a3,d1
		sub.l	a2,d1			;length+1
		cmp.l	#6,d1			;at least "X.RSC"
		blo.s	.no
		lea	-5(a3),a3
		cmp.b	#'.',(a3)+
		bne.s	.no
		move.b	(a3)+,d1
		and.b	#$df,d1
		cmp.b	#'R',d1
		bne.s	.no
		move.b	(a3)+,d1
		and.b	#$df,d1
		cmp.b	#'S',d1
		bne.s	.no
		move.b	(a3),d1
		and.b	#$df,d1
		cmp.b	#'C',d1
		bne.s	.no
		move.w	acc_loadedcnt,d2
		beq.s	.no
		lea	acc_loaded,a3
.entry		move.l	a2,a0
		move.l	a3,a1
.ch		move.b	(a1)+,d1		;loaded name (uppercase)
		beq.s	.next
		move.b	(a0)+,d0		;candidate, uppercased
		cmp.b	#'a',d0
		blo.s	.up
		cmp.b	#'z',d0
		bhi.s	.up
		sub.b	#$20,d0
.up		cmp.b	d0,d1
		bne.s	.next
		cmp.b	#'.',d1			;same stem up to the dot
		bne.s	.ch
		lea	acc_dir,a0
		lea	acc_path,a1
		bsr	acc_strcpy
		subq.l	#1,a1
		move.b	#'\',(a1)+
		move.l	a2,a0
		bsr	acc_strcpy
		moveq	#0,d1			;Z=1
		bra.s	.out
.next		lea	ACCNAMELEN(a3),a3
		subq.w	#1,d2
		bne.s	.entry
.no		moveq	#1,d1			;Z=0
.out		movem.l	(sp)+,d0-d2/a0-a3
		rts

acc_inlist
;in: a1=0-terminated name. out: Z=1 if accepted. preserves registers.
		movem.l	d1-d2/a0-a3,-(sp)
		move.w	acc_listcnt,d2
		beq.s	.yes			;no @acc line: everything
		lea	acc_list,a2
.entry		move.l	a1,a0
		move.l	a2,a3
.ch		move.b	(a3)+,d1
		cmp.b	(a0)+,d1
		bne.s	.next
		tst.b	d1
		bne.s	.ch
		bra.s	.yes
.next		lea	ACCNAMELEN(a2),a2
		subq.w	#1,d2
		bne.s	.entry
		moveq	#1,d1			;Z=0
		bra.s	.out
.yes		moveq	#0,d1			;Z=1
.out		movem.l	(sp)+,d1-d2/a0-a3
		rts

acc_rewrite
;in: a1=filename. out: Z=1 and acc_path = <dir>\<basename> when the
;basename is an accepted accessory name. preserves registers.
		movem.l	d1-d2/a0-a3,-(sp)
		move.l	a1,a2			;basename
		move.l	a1,a3
.scan		move.b	(a3)+,d1
		beq.s	.scanned
		cmp.b	#'\',d1
		beq.s	.sep
		cmp.b	#':',d1
		bne.s	.scan
.sep		move.l	a3,a2
		bra.s	.scan
.scanned	move.l	a3,d1
		sub.l	a2,d1			;length+1
		cmp.l	#6,d1			;at least "X.ACC"
		blo.s	.no
		lea	-5(a3),a3		;".ACC" suffix ?
		cmp.b	#'.',(a3)+
		bne.s	.no
		cmp.b	#'A',(a3)+
		bne.s	.no
		cmp.b	#'C',(a3)+
		bne.s	.no
		cmp.b	#'C',(a3)
		bne.s	.no
		move.l	a2,a1
		bsr	acc_inlist
		bne.s	.no
		lea	acc_dir,a0
		lea	acc_path,a1
		bsr	acc_strcpy
		subq.l	#1,a1
		move.b	#'\',(a1)+
		move.l	a2,a0
		bsr	acc_strcpy
		moveq	#0,d1			;Z=1
		bra.s	.out
.no		moveq	#1,d1			;Z=0
.out		movem.l	(sp)+,d1-d2/a0-a3
		rts


acc_strcpy
.cp		move.b	(a0)+,(a1)+
		bne.s	.cp
		rts

s_staracc	dc.b	"\*.ACC",0
		even
;resident variables (kept in the text segment on purpose)
acc_listcnt	dc.w	0
acc_enum	dc.w	0	;enumeration of <dir>\*.ACC in progress
acc_count	dc.w	0	;Fopen/Pexec(3) still to redirect
acc_loadedcnt	dc.w	0	;accessories accepted (for .RSC lookup)
acc_parm	dc.l	0	;caller parameters during a retry
acc_dir		dcb.b	ACCDIRLEN,0
acc_pattern	dcb.b	ACCDIRLEN+8,0
acc_path	dcb.b	ACCDIRLEN+16,0
acc_env		dcb.b	ACCDIRLEN+8,0
acc_list	dcb.b	ACCMAX*ACCNAMELEN,0
acc_loaded	dcb.b	ACCMAX*ACCNAMELEN,0
		even
acc_res_end

;---------------------------------------------------------------------
acc_parseline
;a0=configline starting with '@' (after cfg_readline). records the setting.
		bsr	cfg_gettoken
		beq	.done
		bsr	cfg_tokentoupper
		lea	tok_accdir,a2
		bsr	strcmptok
		beq	.dir
		lea	tok_acc,a2
		bsr	strcmptok
		bne	.done			;unknown '@' line: ignored
		bsr	cfg_gettoken		;accessory name
		beq	.done
		bsr	cfg_tokentoupper
		move.w	acc_listcnt,d0
		cmp.w	#ACCMAX,d0
		bge	.done
		lsl.w	#4,d0			;*ACCNAMELEN
		lea	acc_list,a1
		add.w	d0,a1
		moveq	#ACCNAMELEN-2,d1
		bsr	acc_strncpy
		addq.w	#1,acc_listcnt
		bra	.on
.dir
		bsr	cfg_gettoken		;directory
		beq	.done
		lea	acc_dir,a1
		moveq	#ACCDIRLEN-2,d1
		bsr	acc_strncpy
		lea	acc_dir,a0		;strip trailing backslash
.fe		tst.b	(a0)+
		bne	.fe
		subq.l	#2,a0
		cmp.b	#'\',(a0)
		bne	.dirok
		clr.b	(a0)
.dirok		move.w	#1,acc_hasdir
.on		move.w	#1,acc_enabled
.done		rts

acc_strncpy
;copies a0 -> a1, at most d1+1 chars, always 0-terminated
.cp		move.b	(a0)+,(a1)+
		beq	.done
		dbra	d1,.cp
		clr.b	(a1)
.done		rts

;---------------------------------------------------------------------
acc_install
;builds the resident strings and hooks trap #1. called before Ptermres.
		tst.w	acc_hasdir
		bne	.hasdir
		lea	def_accdir,a0
		lea	acc_dir,a1
		bsr	strcpy
.hasdir
		lea	acc_dir,a0		;pattern = dir + "\*.ACC"
		lea	acc_pattern,a1
		bsr	strcpy
		subq.l	#1,a1
		lea	s_staracc,a0
		bsr	strcpy
		lea	s_path,a0		;env = "PATH=",0,dir,0,0
		lea	acc_env,a1
		bsr	strcpy
		lea	acc_dir,a0
		bsr	strcpy
		clr.b	(a1)
		tos_supexec	acc_hook_sup
		rts
acc_hook_sup
		move.l	$84.w,acc_oldvec
		move.l	#acc_handler,$84.w
		rts

tok_accdir	dc.b	"@ACCDIR",0
tok_acc		dc.b	"@ACC",0
def_accdir	dc.b	"\ACCS",0
s_path		dc.b	"PATH=",0
		even
	endif	;__mcoldfire__

		section	bss
acc_enabled	ds.w	1	;an '@' line was seen in the selected item
acc_hasdir	ds.w	1
