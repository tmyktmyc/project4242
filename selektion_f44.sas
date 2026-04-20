/*****************************************************************************
 * Selektion F44 - Konten ohne Lastschrifteneinzug nach Fälligkeit
 *
 * Fachliche Beschreibung (nach Mail V. Luening, 20.04.2026):
 *   Ziel: F44-Konten finden, bei denen der turnusmäßige Lastschrifteneinzug
 *         nach dem Fälligkeitsdatum offenbar NICHT angestoßen wurde.
 *
 *   Kriterien:
 *     1) Konto befindet sich aktuell in Pri. Function State = 'F44'
 *     2) Das Fälligkeitsdatum liegt mind. 4 Tage zurück
 *     3) Es besteht noch eine offene Rate (Rückstand > 0)
 *     4) Seit dem Fälligkeitsdatum gab es KEINE Zahlung (ZE)
 *     5) Seit dem Fälligkeitsdatum gab es KEINE Rücklastschrift (RL)
 *
 *   Abgrenzung zu "nicht selektieren": bei Konto 00007119211178 wurde am
 *   14-04-2026 eine Rücklastschrift (RL, 110 EUR) gebucht -> Prozess hat
 *   funktioniert, also ausschließen.
 *   Bei Konto 00007244073149 gibt es seit dem 10-04-2026 keinen RL und
 *   keine (neue) Zahlung -> Prozess klemmt, also selektieren.
 *
 * HINWEIS: Tabellen- und Spaltennamen sind Platzhalter. Bitte ggf. an die
 *          tatsächliche CACS-/DWH-Struktur anpassen (siehe Abschnitt CONFIG).
 *****************************************************************************/


/*---------------------------------------------------------------------------*
 * 0. CONFIG  -- hier die Bibliotheken / Tabellen anpassen
 *---------------------------------------------------------------------------*/
%let LIB_ACC   = DWH;                     /* Libname für Kontenstamm     */
%let LIB_HIST  = DWH;                     /* Libname für Historie        */
%let TAB_ACC   = &LIB_ACC..CACS_KONTO;    /* Kontenstamm (1 Zeile / Konto) */
%let TAB_HIST  = &LIB_HIST..CACS_HISTORIE;/* Ereignis-/Historie-Tabelle  */

%let STICHTAG  = %sysfunc(today());       /* Auswertungsstichtag = heute */
%let MIN_TAGE  = 4;                       /* 4 Tage nach Fälligkeit      */

/* Erwartete Spalten Kontenstamm:
     KONTO_NR              char   Kontonummer (z.B. 00007244073149)
     PRI_FUNCTION_STATE    char   z.B. 'F44'
     NAECHSTE_FAELLIGKEIT  num    Datum nächste Fälligkeit
     RUE_GESAMT            num    Rückstand gesamt (offene Rate)
     DOD                   num    Days of Delinquency (optional)

   Erwartete Spalten Historie:
     KONTO_NR              char
     EVENT_DATUM           num    Datum des Events
     EVENT_CODE            char   z.B. 'RL','ZE','SZ','BA','TA','ZM','EN'
     EVENT_BETRAG          num    Betrag (optional)
*/


/*---------------------------------------------------------------------------*
 * 1. Basis: alle aktuell in F44 befindlichen Konten
 *---------------------------------------------------------------------------*/
proc sql;
    create table work.f44_basis as
    select  KONTO_NR,
            PRI_FUNCTION_STATE,
            NAECHSTE_FAELLIGKEIT  format=ddmmyy10.,
            RUE_GESAMT            format=comma12.2,
            DOD,
            (&STICHTAG - NAECHSTE_FAELLIGKEIT) as TAGE_NACH_FAELLIG
    from    &TAB_ACC
    where   PRI_FUNCTION_STATE = 'F44';
quit;


/*---------------------------------------------------------------------------*
 * 2. Filter: >= 4 Tage nach Fälligkeit UND offene Rate vorhanden
 *---------------------------------------------------------------------------*/
data work.f44_kandidaten;
    set work.f44_basis;
    where TAGE_NACH_FAELLIG >= &MIN_TAGE
      and RUE_GESAMT > 0;
run;


/*---------------------------------------------------------------------------*
 * 3. Historie seit Fälligkeitsdatum einschränken und prüfen, ob es seit
 *    dem Fälligkeitsdatum ein ZE- oder RL-Event gab.
 *---------------------------------------------------------------------------*/
proc sql;
    create table work.events_seit_faellig as
    select  k.KONTO_NR,
            k.NAECHSTE_FAELLIGKEIT,
            max(case when h.EVENT_CODE = 'RL'
                      and h.EVENT_DATUM >= k.NAECHSTE_FAELLIGKEIT
                     then 1 else 0 end) as HAS_RL,
            max(case when h.EVENT_CODE = 'ZE'
                      and h.EVENT_DATUM >= k.NAECHSTE_FAELLIGKEIT
                     then 1 else 0 end) as HAS_ZE
    from    work.f44_kandidaten k
    left join &TAB_HIST           h
      on    h.KONTO_NR = k.KONTO_NR
    group by k.KONTO_NR, k.NAECHSTE_FAELLIGKEIT;
quit;


/*---------------------------------------------------------------------------*
 * 4. Finale Selektion: weder ZE noch RL seit Fälligkeit
 *---------------------------------------------------------------------------*/
proc sql;
    create table work.selektion_f44 as
    select  k.KONTO_NR,
            k.PRI_FUNCTION_STATE,
            k.NAECHSTE_FAELLIGKEIT  format=ddmmyy10.,
            k.TAGE_NACH_FAELLIG     label='Tage nach Fälligkeit',
            k.RUE_GESAMT            format=comma12.2,
            k.DOD
    from    work.f44_kandidaten k
    inner join work.events_seit_faellig e
      on    e.KONTO_NR = k.KONTO_NR
    where   e.HAS_RL = 0
      and   e.HAS_ZE = 0
    order by k.KONTO_NR;
quit;


/*---------------------------------------------------------------------------*
 * 5. Kontrolle: Prüfung gegen die von Vanessa genannten Beispiele
 *     Soll selektiert werden:
 *       00007291538685, 00007244073149, 00007224078009,
 *       00007293143807, 00007253693813
 *     Soll NICHT selektiert werden:
 *       00007231231659, 00007109400756, 00007119211178, 00007215282288
 *---------------------------------------------------------------------------*/
data work.check_beispiele;
    length KONTO_NR $20 ERWARTET $12;
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
    create table work.check_ergebnis as
    select  b.KONTO_NR,
            b.ERWARTET,
            case when s.KONTO_NR is not null then 'JA' else 'NEIN' end
                 as IST_SELEKTIERT length=4,
            case when (b.ERWARTET = 'SELEKT' and s.KONTO_NR is not null)
                   or (b.ERWARTET = 'NICHT'  and s.KONTO_NR is null)
                 then 'OK'
                 else 'ABWEICHUNG'
            end  as PRUEFUNG length=10
    from    work.check_beispiele b
    left join work.selektion_f44 s
      on    s.KONTO_NR = b.KONTO_NR
    order by b.ERWARTET desc, b.KONTO_NR;
quit;

title "Selektion F44 - Ergebnisabgleich mit den Beispielkonten";
proc print data=work.check_ergebnis noobs; run;
title;

title "Selektion F44 - finale Trefferliste (Stichtag = heute)";
proc print data=work.selektion_f44 noobs; run;
title;
