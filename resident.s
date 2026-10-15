;resident.s - terminate and stay resident with the smallest footprint.
;must be the LAST code included: everything before goresident may be
;overwritten by the cookie jar copy.
;
;kept by Ptermres: basepage + [hook block of acc.s, if '@' lines were
;used] + [cookie jar of .jar, moved right behind]. about 1 KB for
;".jar 100" instead of the whole program.

		section	code
goresident
	ifnd	__mcoldfire__
		tst.w	acc_enabled
		beq	.noacc
		bsr	acc_install		;hook trap #1 (acc.s)
		move.l	#acc_res_end,d0		;keep the hook block
		bra	.setend
.noacc
	endif
		move.l	#res_start,d0		;nothing kept so far
.setend		move.l	d0,res_end
		tst.w	v_jar
		beq	.nojar
		pea	movejar_sup		;move the jar behind (supervisor)
		move.w	#38,-(sp)
		trap	#14
		addq.l	#6,sp
.nojar
		tst.w	res_full
		bne	.keepall
		move.l	res_end,d0
		cmp.l	#res_start,d0		;nothing to keep (jar replaced
		beq	.pterm			;by someone else, no hook)
		sub.l	v_basepage,d0
		bra	.term
.keepall	move.l	v_basepage,a5		;fallback: keep everything
		move.l	$0c(a5),d0
		add.l	$14(a5),d0
		add.l	$1c(a5),d0
		add.l	#$100+1024,d0
.term		tos_ptermres d0,#0
.pterm		tos_pterm0

movejar_sup
;copies our jar (jarbuffer, including cookies added since) to res_end,
;repoints _p_cookies and advances res_end. sets res_full if the copy
;would reach this code.
		move.l	#ptr_cookiejar,a1
		move.l	(a1),a0
		cmp.l	#jarbuffer,a0		;still our jar ?
		bne	.done
		move.l	a0,a2
		moveq	#1,d1			;entries to copy (with terminator)
.find		tst.l	(a2)
		beq	.found
		addq.l	#8,a2
		addq.l	#1,d1
		bra	.find
.found		move.l	4(a2),d0		;capacity
		addq.l	#1,d0
		lsl.l	#3,d0			;bytes reserved
		move.l	res_end,a2		;destination
		add.l	a2,d0			;new end
		cmp.l	#goresident,d0
		bhi	.full
		move.w	sr,d2
		move.w	#$2700,sr
		move.l	a2,(a1)			;_p_cookies -> resident copy
.copy		move.l	(a0)+,(a2)+
		move.l	(a0)+,(a2)+
		subq.l	#1,d1
		bne	.copy
		move.w	d2,sr
		move.l	d0,res_end
.done		rts
.full		moveq	#1,d0
		move.w	d0,res_full
		rts

		section	bss
res_end		ds.l	1	;end of the resident area
res_full	ds.w	1	;1 = keep the whole program
