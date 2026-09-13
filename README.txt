insaneBOOT - etat du projet
===========================

Objectif : menu de boot Atari (ST/STE/TT/Falcon/Coldfire) qui lance des
programmes selon la config autoexec.cfg. Ne modifie pas le disque.

Detection materielle (supcode.s, via cookies systeme) :
- c_cpu  : cookie _CPU (0/10/20/30/40/60 = 68000..68060)
- c_mch  : cookie _MCH (type de machine)
- c_tosver : os_version (_sysbase $4f2 +2 ; $0206=2.06, $0162=1.62)
             affichable via .showtos ("TOS x.xx", octet bas en BCD).
             EmuTOS renvoie aussi $0206 (cookie ETOS a etudier pour le
             distinguer d'un vrai TOS 2.06).
- shiftres : registre $ffff8260 & %11 (0/1 = couleur, 2 = mono/haute res)

Flags d'items conditionnels (parser.s) :
- CPU seul        : .ITEM000 .ITEM010 .ITEM020 .ITEM030 .ITEM040 .ITEM060
- Resolution seule: .ITEMSTC (couleur)  .ITEMSTM (mono/haute res)
- Combines (res+CPU, ajoutes le 2026-09-11) :
    .ITEMSTC000  couleur + 68000
    .ITEMSTM000  mono    + 68000
    .ITEMSTC020  couleur + 68020
    .ITEMSTM020  mono    + 68020
Chaque handler enchaine les tests (bne skipitem) avant handle_item ;
ajouter une combinaison = 3 lignes (chktoken + handler + token).

Directives globales notables :
- .jar N  : reserve un cookie jar resident de N cookies (max 128),
  remplace jarXXX.prg. Recopie les cookies existants, ecrit le
  terminateur {0,capacite} et repointe _p_cookies ($5a0) sur un buffer
  BSS (jarbuffer). Quand .jar est present, insaneboot sort par Ptermres
  (au lieu de Pterm0) pour rester resident et conserver le jar.
  Code : handle_jar (parser.s), installjar/installjar_sup (supcode.s),
  install + Ptermres conditionnel (autoexec.s).
- .foldr : NON implemente (obsolete). FOLDRXXX.PRG est un no-op sur
  TOS >= 1987 et n'a des adresses codees en dur que pour 4 ROMs 1985-86.
  Sur EmuTOS / TOS 1.62 / 2.06 la gestion des FRB est dynamique.

Build : `make all` (68k) ; `make cf` (cible Coldfire cf5474).
vasmm68k_mot est dans ~/.local/opt/ (ajouter au PATH si besoin).
Etat : les deux cibles compilent (vasm 2.0f) avec les flags combines
et la directive .jar. .jar non encore teste en emulateur/reel (a valider
sous EmuTOS et TOS 1.62/2.06, ex. via un dumpeur de cookies).
NB Coldfire : shiftres n'est pas initialise (mis a jour uniquement en
build 68k, cf supcode.s), donc les variantes STC/STM y sont toujours
traitees comme "couleur" -- comportement pre-existant, inchange.
