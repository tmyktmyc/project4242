/*****************************************************************************
 * Selektion F44 - Konten ohne Lastschrifteneinzug nach Fälligkeit
 *
 * Regel:
 *   V_CLE_CACS_STATE_CODE = 'F44'  (aus MISEXT_C)
 *   UND  (heute - D_ALSLN_RT_NXT_DUE_DATE) >= 4
 *   UND  N_ALSLN_DQ_TOT_AMT_PDUE > 0
 *   UND  keine Rücklastschrift (TRAN_CD='9583', GEN_IND='N') in
 *        vedw.Dri_276_ed_als_txn_nc seit D_ALSLN_RT_NXT_DUE_DATE
 *
 * Quellen:
 *   vedw.DRI_276_ED_MISEXT_C      State-Code je Konto (V_CLE_CACS_STATE_CODE)
 *   vedw.Dri_276_ed_als_loan_nc   Fälligkeit / Rückstand (D_ALSLN_RT_NXT_DUE_DATE,
 *                                                         N_ALSLN_DQ_TOT_AMT_PDUE)
 *   vedw.Dri_276_ed_als_txn_nc    Transaktionen (RL = 9583 / N)
 *****************************************************************************/

%include "/home/ldap/&sysuserid./tbkdcol/fidat/MACROLIB/Misdate_guide.sas";


/*--- finale Selektion in einem Rutsch ---------------------------------------*/
proc sql;
    create table work.selektion_f44 as
    select  m.V_CLE_ACCT_NBR                           as A_ACC,
            m.V_CLE_CACS_STATE_CODE                    as C_STATE,
            l.D_ALSLN_RT_NXT_DUE_DATE                  as D_DUE_DAT  format=ddmmyy10.,
            (&today. - l.D_ALSLN_RT_NXT_DUE_DATE)      as TAGE_NACH_FAELLIG
                                                          label='Tage nach Faelligkeit',
            l.N_ALSLN_DQ_TOT_AMT_PDUE                  as N_PDUE_AMT format=comma12.2
    from    vedw.DRI_276_ED_MISEXT_C      m
    inner join vedw.Dri_276_ed_als_loan_nc l
      on    l.V_ALSLN_ORIG_ACCT_NBR = m.V_CLE_ACCT_NBR
     and    l.MIS_DATE              = m.MIS_DATE
    where   m.MIS_DATE               = &today.
      and   m.V_CLE_CACS_STATE_CODE  = 'F44'
      and   (&today. - l.D_ALSLN_RT_NXT_DUE_DATE) >= 4
      and   l.N_ALSLN_DQ_TOT_AMT_PDUE > 0
      and   not exists (
                select 1
                from   vedw.Dri_276_ed_als_txn_nc t
                where  t.V_ALSTXN_ORIG_ACCT_NBR = m.V_CLE_ACCT_NBR
                  and  t.V_ALSTXN_TR_TRAN_CD    = '9583'
                  and  t.V_ALSTXN_TR_GEN_IND    = 'N'
                  and  t.D_ALSTXN_TR_PROC_DATE >= l.D_ALSLN_RT_NXT_DUE_DATE
            )
    order by A_ACC;
quit;


/*--- Abgleich mit den Beispielkonten von Vanessa (inline) -------------------*/
proc sql;
    create table work.selektion_f44_check as
    select  b.A_ACC,
            b.ERWARTET,
            case when s.A_ACC is not null then 'JA' else 'NEIN' end
                 as IST_SELEKTIERT length=4,
            case when (b.ERWARTET='SELEKT' and s.A_ACC is not null)
                   or (b.ERWARTET='NICHT'  and s.A_ACC is null)
                 then 'OK' else 'ABWEICHUNG'
            end  as PRUEFUNG length=10
    from (
            select '00007291538685' as A_ACC length=20, 'SELEKT' as ERWARTET length=8 from sashelp.class(obs=1) union all
            select '00007244073149',                     'SELEKT'                      from sashelp.class(obs=1) union all
            select '00007224078009',                     'SELEKT'                      from sashelp.class(obs=1) union all
            select '00007293143807',                     'SELEKT'                      from sashelp.class(obs=1) union all
            select '00007253693813',                     'SELEKT'                      from sashelp.class(obs=1) union all
            select '00007231231659',                     'NICHT'                       from sashelp.class(obs=1) union all
            select '00007109400756',                     'NICHT'                       from sashelp.class(obs=1) union all
            select '00007119211178',                     'NICHT'                       from sashelp.class(obs=1) union all
            select '00007215282288',                     'NICHT'                       from sashelp.class(obs=1)
         ) b
    left join work.selektion_f44 s on s.A_ACC = b.A_ACC
    order by b.ERWARTET desc, b.A_ACC;
quit;

title "Selektion F44 - Abgleich mit Beispielkonten";
proc print data=work.selektion_f44_check noobs; run;
title "Selektion F44 - finale Trefferliste (Stichtag &today.)";
proc print data=work.selektion_f44       noobs; run;
title;
