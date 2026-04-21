/*****************************************************************************
 * Selektion F44 - Konten ohne Lastschrifteneinzug nach Fälligkeit
 *
 * Datumslogik:
 *   &datmisext.  = MIS-Stichtag (letzter Arbeitstag, NICHT heute)
 *                  -> wird für MIS_DATE-Filter verwendet
 *   &today.      = tatsächlicher heutiger Tag
 *                  -> wird für "4 Tage nach Fälligkeitsdatum" verwendet
 *
 * Ablauf in einfachen Schritten:
 *   1) F44-Konten holen                (aus vedw.DRI_276_ED_MISEXT_C)
 *   2) Fälligkeit/Rückstand dranhängen (aus vedw.Dri_276_ed_als_loan_nc)
 *      -> Filter: >= 4 Tage nach Fälligkeit UND Rückstand > 0
 *   3) Konten mit Rücklastschrift nach Fälligkeit suchen
 *                                      (aus vedw.Dri_276_ed_als_txn_nc,
 *                                       TRAN_CD='9583' und GEN_IND='N')
 *   4) Finale Selektion = Schritt 2 OHNE Schritt 3
 *   5) Abgleich mit den Beispielkonten von Vanessa
 *****************************************************************************/

%include "/home/ldap/&sysuserid./tbkdcol/fidat/MACROLIB/Misdate_guide.sas";


/*---------------------------------------------------------------------------*
 * Schritt 1: alle aktuell in State F44 befindlichen Konten
 *---------------------------------------------------------------------------*/
proc sql;
    create table work.s1_f44_konten as
    select  V_CLE_ACCT_NBR        as A_ACC,
            V_CLE_CACS_STATE_CODE as C_STATE
    from    vedw.DRI_276_ED_MISEXT_C
    where   MIS_DATE              = "&datmisext."d
      and   V_CLE_CACS_STATE_CODE = 'F44';
quit;


/*---------------------------------------------------------------------------*
 * Schritt 2: Fälligkeit und Rückstand dranhängen,
 *            >= 4 Tage nach Fälligkeit UND Rückstand > 0
 *---------------------------------------------------------------------------*/
proc sql;
    create table work.s2_kandidaten as
    select  k.A_ACC,
            k.C_STATE,
            l.D_ALSLN_RT_NXT_DUE_DATE               as D_DUE_DAT   format=ddmmyy10.,
            (&today. - l.D_ALSLN_RT_NXT_DUE_DATE)   as TAGE_NACH_FAELLIG
                                                       label='Tage nach Faelligkeit',
            l.N_ALSLN_DQ_TOT_AMT_PDUE               as N_PDUE_AMT  format=comma12.2
    from    work.s1_f44_konten            k
    inner join vedw.Dri_276_ed_als_loan_nc l
      on    l.V_ALSLN_ORIG_ACCT_NBR = k.A_ACC
     and    l.MIS_DATE              = "&datmisext."d
    where   (&today. - l.D_ALSLN_RT_NXT_DUE_DATE) >= 4
      and   l.N_ALSLN_DQ_TOT_AMT_PDUE > 0;
quit;


/*---------------------------------------------------------------------------*
 * Schritt 3: Konten mit Rücklastschrift seit Fälligkeitsdatum (AUSSCHLIESSEN)
 *            Rücklastschrift = TRAN_CD '9583' + GEN_IND 'N'
 *---------------------------------------------------------------------------*/
proc sql;
    create table work.s3_konten_mit_rl as
    select distinct
            k.A_ACC
    from    work.s2_kandidaten         k
    inner join vedw.Dri_276_ed_als_txn_nc t
      on    t.V_ALSTXN_ORIG_ACCT_NBR = k.A_ACC
    where   t.V_ALSTXN_TR_TRAN_CD    = '9583'
      and   t.V_ALSTXN_TR_GEN_IND    = 'N'
      and   t.D_ALSTXN_TR_PROC_DATE >= k.D_DUE_DAT;
quit;


/*---------------------------------------------------------------------------*
 * Schritt 4: finale Selektion = Kandidaten OHNE RL seit Fälligkeit
 *---------------------------------------------------------------------------*/
proc sql;
    create table work.s4_selektion_f44 as
    select  k.*
    from    work.s2_kandidaten k
    where   k.A_ACC not in (select A_ACC from work.s3_konten_mit_rl)
    order by k.A_ACC;
quit;


/*---------------------------------------------------------------------------*
 * Schritt 5: Abgleich mit den Beispielkonten von Vanessa
 *---------------------------------------------------------------------------*/
data work.s5_beispiele;
    length A_ACC $20 ERWARTET $8;
    input A_ACC $ ERWARTET $;
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
    select  b.A_ACC,
            b.ERWARTET,
            case when s.A_ACC is not null then 'JA' else 'NEIN' end
                 as IST_SELEKTIERT length=4,
            case when (b.ERWARTET='SELEKT' and s.A_ACC is not null)
                   or (b.ERWARTET='NICHT'  and s.A_ACC is null)
                 then 'OK' else 'ABWEICHUNG'
            end  as PRUEFUNG length=10
    from    work.s5_beispiele b
    left join work.s4_selektion_f44 s
      on    s.A_ACC = b.A_ACC
    order by b.ERWARTET desc, b.A_ACC;
quit;


title "Selektion F44 - Abgleich mit Beispielkonten";
proc print data=work.s5_abgleich noobs; run;
title "Selektion F44 - finale Trefferliste (Stichtag &today.)";
proc print data=work.s4_selektion_f44 noobs; run;
title;
