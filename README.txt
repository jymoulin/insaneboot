insaneBOOT - etat du projet
===========================

Objectif : menu de boot Atari (ST/STE/TT/Falcon/Coldfire) qui lance des
programmes selon la config autoexec.cfg. Ne modifie pas le disque.

Detection materielle (supcode.s, via cookies systeme) :
- c_cpu  : cookie _CPU (0/10/20/30/40/60 = 68000..68060)
- c_mch  : cookie _MCH (type de machine)
- c_tosver : os_version (_sysbase $4f2 +2 ; $0206=2.06, $0162=1.62)
             affichable via .showtos ("TOS x.xx", octet bas en BCD).
             EmuTOS renvoie aussi $0206 : detecte par "ETOS" a
             l'offset $2c de l'en-tete OS (c_emutos) ; .showtos
             n'affiche alors rien (EmuTOS montre deja sa version).
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
- .jar N  : cookie jar resident de N places AU TOTAL (cookies existants
  compris ; remplace jarXXX.prg), max 128 ; releve a existants+1 si N
  est trop petit.
  installjar_sup (supcode.s) construit le jar dans jarbuffer (BSS) avant
  de lancer l'item ; a la sortie il est recopie dans la zone residente.
- Residence minimale (resident.s, DOIT rester le dernier include code) :
  acc.s est inclus tout au debut du texte (res_start: bra start) avec
  le hook et ses variables jusqu'a acc_res_end. goresident garde par
  Ptermres : basepage + [bloc hook si lignes '@'] + [jar recopie juste
  derriere, _p_cookies repointe]. Mesure : .jar 20 = 480 o, @acc = 1776 o,
  les deux = 2000 o (au lieu de ~9 Ko). Si le jar n'est plus le notre
  ou s'il n'y a rien a garder -> Pterm0 ; si la copie atteignait
  goresident -> repli sur tout le programme.
- @accdir <dir> / @acc NOM.ACC (lignes '@' DANS un bloc .item, acc.s) :
  accessoires du bureau par item, remplace ACC.PRG (cf ../acc/). Hook
  GEMDOS resident (trap #1, XBRA "ISNB") : Fsfirst("\*.ACC") de l'AES ->
  <dir>\*.ACC, Fsnext filtre les noms hors liste (appel imbrique de
  l'ancien vecteur + lecture DTA+30), puis Fopen/Pexec(3,"NOM.ACC") ->
  <dir>\NOM.ACC (+2 par nom accepte, -1 par appel reecrit). Frame 68000
  ou 68010+ via _longframe ($59e), parametres sur USP ou SSP. 68k
  uniquement (ignore sur ColdFire). Installe dans terminate avant
  Ptermres (residence partagee avec .jar). Valide sous Hatari (traces
  gemdos+aes) : TOS 2.06 et EmuTOS chargent exactement la liste.
  Les NOM.RSC d'un accessoire charge sont cherches dans <dir> si la
  recherche d'origine echoue (Fsfirst/Fopen reessayes).
- .magicquit 1 : sort des la lecture si cookie MagX (passe MagiC apres
  MAGXBOOT) ; remet v_jar a 0 -> pas de Ptermres inutile.
- .foldr : NON implemente (obsolete). FOLDRXXX.PRG est un no-op sur
  TOS >= 1987 et n'a des adresses codees en dur que pour 4 ROMs 1985-86.
  Sur EmuTOS / TOS 1.62 / 2.06 la gestion des FRB est dynamique.

Build : `make all` (68k) ; `make cf` (cible Coldfire cf5474).
vasmm68k_mot est dans ~/.local/opt/ (ajouter au PATH si besoin).
Etat : les deux cibles compilent (vasm 2.0f). .jar, .showtos et les
accessoires par item (@accdir/@acc) sont valides sous Hatari en ST
(TOS 2.06 + EmuTOS, 68000) et en Falcon (TOS 4.04, 68030 : frames
longues _longframe + USP OK) ; reste a valider sur machine reelle
(binaires dans ~/Downloads/ToTest/INSANEBT/, cf todo_insaneboot.txt).
Test emulateur : Hatari -d <dir> --run-vbls N --trace gemdos,aes
(--conout 2 pour capturer l'affichage). Falcon : --machine falcon
--tos tos404fr.img et OBLIGATOIREMENT --fast-boot on, sinon TOS 4.04
boote sur A: et n'execute pas C:\AUTO (la cle bBootFromHardDisk ne
suffit pas).
Abandonnes : .foldr (obsolete), pilotage I2C du TwiSTEr (TOSWIT_4 reste
lance comme item), regles par version de TOS (a voir a l'usage).
NB Coldfire : shiftres n'est pas initialise (mis a jour uniquement en
build 68k, cf supcode.s), donc les variantes STC/STM y sont toujours
traitees comme "couleur" -- comportement pre-existant, inchange.
