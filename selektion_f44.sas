/*****************************************************************************
 * Selektion F44 - Konten ohne Lastschrifteneinzug nach Fälligkeit
 *
 * Fachliche Logik (nach Mail V. Luening, 20.04.2026 + Beispielabgleich):
 *   Selektiere Konten, bei denen
 *     1) Pri. Function State = 'F44'
 *     2) Fälligkeitsdatum (NAECHSTE_FAELLIGKEIT) liegt >= 4 Tage zurück
 *     3) Rückstand vorhanden (RUE_GESAMT > 0)
 *     4) Seit dem Fälligkeitsdatum KEINE Rücklastschrift (Event-Code 'RL')
 *
 *   Das RL-Kriterium ist das Unterscheidungsmerkmal zwischen "selektieren"
 *   und "nicht selektieren" (Beispiele 00007109400756, 00007119211178,
 *   00007215282288 haben alle ein RL-Event 13./14./16.-04.).
 *
 * Datenquelle: eine einzige Tabelle, die je Konto sowohl die aktuellen
 *              Stammdaten als auch die Historie-Events enthält (Long-Format,
 *              eine Zeile je Event).
 * Stichtag:    Makrovariable &today.
 *
 * HINWEIS: Tabellen-/Spaltennamen sind Platzhalter, bitte an Produktion
 *          anpassen (siehe CONFIG).
 *****************************************************************************/


/*---------------------------------------------------------------------------*
 * 0. CONFIG
 *---------------------------------------------------------------------------*/
%let TAB_SRC  = DWH.CACS_KONTO_HIST;   /* eine Tabelle, Long-Format */
%let MIN_TAGE = 4;                     /* 4 Tage nach Fälligkeit    */

/* Erwartete Spalten in &TAB_SRC:
     KONTO_NR              char
     PRI_FUNCTION_STATE    char   aktueller State, z.B. 'F44'
     NAECHSTE_FAELLIGKEIT  num    Datum der offenen Fälligkeit
     RUE_GESAMT            num    aktueller Rückstand
     EVENT_DATUM           num    Datum des Events
     EVENT_CODE            char   z.B. 'RL','ZE','SZ','BA','TA','EN','ZM','KI','BP'
     EVENT_BETRAG          num    Betrag zum Event (optional)
*/


/*---------------------------------------------------------------------------*
 * 1. Alle aktuell in F44 befindlichen Konten (distinct, 1 Zeile je Konto)
 *---------------------------------------------------------------------------*/
proc sql;
    create table work.s1_f44_konten as
    select distinct
            KONTO_NR,
            PRI_FUNCTION_STATE,
            NAECHSTE_FAELLIGKEIT  format=ddmmyy10.,
            RUE_GESAMT            format=comma12.2
    from    &TAB_SRC
    where   PRI_FUNCTION_STATE = 'F44';
quit;


/*---------------------------------------------------------------------------*
 * 2. Filter: >= 4 Tage nach Fälligkeit UND Rückstand > 0
 *---------------------------------------------------------------------------*/
data work.s2_kandidaten;
    set work.s1_f44_konten;
    TAGE_NACH_FAELLIG = &today. - NAECHSTE_FAELLIGKEIT;
    if TAGE_NACH_FAELLIG >= &MIN_TAGE
       and RUE_GESAMT > 0;
run;


/*---------------------------------------------------------------------------*
 * 3. Konten mit einer Rücklastschrift (RL) nach Fälligkeitsdatum
 *    -> diese sind AUSZUSCHLIESSEN
 *---------------------------------------------------------------------------*/
proc sql;
    create table work.s3_konten_mit_rl as
    select distinct k.KONTO_NR
    from    work.s2_kandidaten k
    inner join &TAB_SRC h
      on    h.KONTO_NR    = k.KONTO_NR
     and    h.EVENT_CODE  = 'RL'
     and    h.EVENT_DATUM >= k.NAECHSTE_FAELLIGKEIT;
quit;


/*---------------------------------------------------------------------------*
 * 4. Finale Selektion: Kandidaten OHNE RL seit Fälligkeit
 *---------------------------------------------------------------------------*/
proc sql;
    create table work.s4_selektion_f44 as
    select  k.KONTO_NR,
            k.PRI_FUNCTION_STATE,
            k.NAECHSTE_FAELLIGKEIT  format=ddmmyy10.,
            k.TAGE_NACH_FAELLIG     label='Tage nach Fälligkeit',
            k.RUE_GESAMT            format=comma12.2
    from    work.s2_kandidaten k
    where   k.KONTO_NR not in (select KONTO_NR from work.s3_konten_mit_rl)
    order by k.KONTO_NR;
quit;


/*---------------------------------------------------------------------------*
 * 5. Kontrolle gegen die Beispielkonten von Vanessa
 *---------------------------------------------------------------------------*/
data work.s5_beispiele;
    length KONTO_NR $20 ERWARTET $8;
    input KONTO_NR $ ERWARTET $;
    datalines;
00007291538685 SELEKT
00007244073149 SELEKT
00007224078009 SELEKT
00007293143807 SELEKT
00007253693813 SELEKT
00007231231659 NICHT
00007109400756 NICHT
00007119211178 NICHT
00007215282288 NICHT
;
run;

proc sql;
    create table work.s5_abgleich as
    select  b.KONTO_NR,
            b.ERWARTET,
            case when s.KONTO_NR is not null then 'JA' else 'NEIN' end
                 as IST_SELEKTIERT length=4,
            case when (b.ERWARTET = 'SELEKT' and s.KONTO_NR is not null)
                   or (b.ERWARTET = 'NICHT'  and s.KONTO_NR is null)
                 then 'OK' else 'ABWEICHUNG'
            end  as PRUEFUNG length=10
    from    work.s5_beispiele b
    left join work.s4_selektion_f44 s
      on    s.KONTO_NR = b.KONTO_NR
    order by b.ERWARTET desc, b.KONTO_NR;
quit;


title "Selektion F44 - Abgleich mit Beispielkonten";
proc print data=work.s5_abgleich noobs; run;
title "Selektion F44 - finale Trefferliste (Stichtag &today.)";
proc print data=work.s4_selektion_f44 noobs; run;
title;
