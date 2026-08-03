/************* Systemvariablen für Datum bereitstellen ************/
%include "/home/ldap/&sysuserid./tbkdcol/fidat/MACROLIB/Misdate_guide.sas";

/*
1. Portfolio auf nicht ausgebuchte Vergleiche prüfen (wg Asset Sale)

2. weitere Ausbuchungspotenziale ermitteln
	a) älter als 79
	b) kein ZE letzte 12 Monate
	c) Blacklistkriterium
	d) ein Kunde ist settled
	e) Restantalter
	f) Fraud: E38/39
	g) Compliance: E32
	h) Karten mit HRSL <= 2010
	i) Kunde unter Betreuung

*/

/* Asset Sale 2026 einbinden */
libname Sale2026 "/home/ldap/&sysuserid./tbkd/tbkdcmn/tbkcreshare/decrecol/Asset_Sale_2026";

libname AS_2026 "/home/ldap/&sysuserid./tbkdcol/AS_2026";

data Konten1;
set Sale2026.SALE_POTENTIAL_IFRS9_202606V34;
/*if CACS_STATE in ("A66", "A67");*/
KtoNr = ACCOUNT_NO;
if CARD_NBR ne "" then KtoNr = CARD_NBR;
run;

/* CIN1 und CIN2 an Sale2026-Selektion anfügen */
proc sql;
	create table reln as
	select	MIS_DATE,
			V_RM_RELN_CUSTNUMB,
			V_RM_RELN_CUST_PRIM_IND,
			V_RM_RELN_ORIG_ACCT_NBR,
			V_RM_RELN_PROD_SUBTYPE,
			V_RM_RELN_ACCTNUMB,
			V_RM_RELN_SUBSYS
	from VEDW.Dri_276_ebs_rm_reln_nc
	where	mis_date = "30JUN2026"d
	and input(V_RM_RELN_ORIG_ACCT_NBR,16.) in (select input(ACCOUNT_NO,16.) from Konten1)
		and V_RM_RELN_CUST_PRIM_IND = 'Y'/*Kunde 1*/
		and V_WBB_SOURCE_FLAG = 'EBS'
		and V_RM_RELN_RELNCATG = 'D'/*nur direkte Kundenverbindungen*/
	;
quit;

/*  Nach SUBSYS sortieren, so steht "AM" mit orig-Kontonummer mit führenden Nullen oben*/
proc sort data=reln;
	by V_RM_RELN_ACCTNUMB V_RM_RELN_CUSTNUMB V_RM_RELN_SUBSYS;
run;

/*  werfe die Doppelten Einträge raus	*/
proc sort data=reln nodupkey;
	by V_RM_RELN_ACCTNUMB V_RM_RELN_CUSTNUMB ;
run;

proc sql;
	create table Konten1 as
	select a.*, b.V_RM_RELN_CUSTNUMB as CIN1
	from Konten1 as a left join reln as b
	on input(a.ACCOUNT_NO,16.)=input(b.V_RM_RELN_ORIG_ACCT_NBR,16.)
	;
quit;

proc sql;
	create table reln2 as
	select	MIS_DATE,
			V_RM_RELN_CUSTNUMB,
			V_RM_RELN_CUST_PRIM_IND,
			V_RM_RELN_ORIG_ACCT_NBR,
			V_RM_RELN_PROD_SUBTYPE,
			V_RM_RELN_ACCTNUMB,
			V_RM_RELN_SUBSYS
	from VEDW.Dri_276_ebs_rm_reln_nc
	where	mis_date = "30JUN2026"d
	and input(V_RM_RELN_ORIG_ACCT_NBR,16.) in (select input(ACCOUNT_NO,16.) from Konten1)
		and V_RM_RELN_CUST_PRIM_IND = 'N'/*Kunde 2*/
		and V_WBB_SOURCE_FLAG = 'EBS'
		and V_RM_RELN_RELNCATG = 'D'/*nur direkte Kundenverbindungen*/
	;
quit;

/*  Nach SUBSYS sortieren, so steht "AM" mit orig-Kontonummer mit führenden Nullen oben*/
proc sort data=reln2;
	by V_RM_RELN_ACCTNUMB V_RM_RELN_CUSTNUMB V_RM_RELN_SUBSYS;
run;

/*  werfe die Doppelten Einträge raus	*/
proc sort data=reln2 nodupkey;
	by V_RM_RELN_ACCTNUMB V_RM_RELN_CUSTNUMB ;	/* [verdeckt vom Tooltip - bitte prüfen] */
run;

proc sql;
	create table Konten1 as
	select a.*, b.V_RM_RELN_CUSTNUMB as CIN2	/* [teilw. verdeckt - bitte prüfen] */
	from Konten1 as a left join reln2 as b		/* [teilw. verdeckt - bitte prüfen] */
	on input(a.ACCOUNT_NO,16.)=input(b.V_RM_RELN_ORIG_ACCT_NBR,16.)
	;
quit;

/* Kundendaten ermitteln */
proc sql;
	create table cust as
	select
			MIS_DATE,
			V_RMCUST_CUSTNUMB,
/*			V_RMCUST_ADDR_LINE3 as Strasse,
			V_RMCUST_ADDR_LINE4 as Zusatz,
			V_RMCUST_POST_CODE as PLZ,
			V_RMCUST_TOWNCITY_DESC as Ort,*/
			intck('year',D_RMCUST_BIRTH_DATE,Today())  as Alter,
			V_RMCUST_OK_TO_CALL,
			V_RMCUST_DECESIND,
			D_CM_CUST_DATE_OF_DEATH,
			V_CUST_UNDER_CUSTODIAN_FLG,
			V_RMCUST_HOME_PH_NBR,
			V_RMCUST_MOBILE_PH_NBR,
			V_RMCUST_EMAIL_ADDR_1,
			V_RMCUST_EMAIL_ADDR_2,
			V_RMCUST_OK_TO_EMAIL
/*			,V_RMCUST_NATLCODE,
			V_RMCUST_BIRTH_PLACE,
			V_RMCUST_BIRTH_CTRY,
			V_RMCUST_DOMCODE */
	from VEDW.Dri_276_ed_rm_cust_c
	where MIS_DATE="&datreln."d;
quit;

/* settled Kunden identifizieren */
proc sql;
	create table ext as
	select distinct
			V_CLE_ACCT_NBR as KONTONUMMER,
			V_CLE_CUST_INFO_NBR,
			V_CLE_ACCT_NBR as KtoNr,
			V_CLE_CACS_STATE_CODE as State, substr(V_CLE_CACS_STATE_CODE,1,1) as LOC,
			N_CLE_BALANCE_AMT as Kontosaldo,
			D_CLE_LAST_PAYMENT_DATE,
			N_CLE_LAST_PAYMENT_AMT as LAST_PAYMENT_AMT,
			V_CLE_BUSINESS_ADDR_ST_1,
			V_CLE_SECONDARY_CUST_NAME
	from vedw.dri_276_ed_misext_c as b
	where MIS_DATE = "&datreln."d;
quit;

data ext;
set ext;
format Settled_kn1 $4.;
format Settled_kn2 $4.;
if V_CLE_BUSINESS_ADDR_ST_1 = "SETTLED" then Settled_kn1='ja';
else Settled_kn1='nein';
if V_CLE_SECONDARY_CUST_NAME = "SETTLED" then Settled_kn2='ja';
else Settled_kn2='nein';
run;

/* Datum letzte HRSL (Open Date) aus CACS anfügen */
proc sql;
	create table extnc as
	select V_CLE_ACCT_NBR, D_CLE_ACCT_OPEN_DATE as OPEN_DATE format date9.
	from VEDW.dri_276_ed_misext_nc
	where MIS_DATE="&datreln."d;
quit;

/* alle Daten zusammenfügen */
proc sql;
	create table Konten2 as select a.*, b.*, c.* from
	Konten1 as a
	left join
	Cust as b
	on input(a.CIN1,14.) = input(b.V_RMCUST_CUSTNUMB,14.)
	left join
	ext as c
	on a.KtoNr = c.KONTONUMMER;
quit;

proc sql;
	create table Konten2 as select a.*, b.OPEN_DATE from
	Konten2 as a
	left join
	extnc as b
	on a.KtoNr = b.V_CLE_ACCT_NBR;
quit;

/* ausgewählte Infos für CIN2 anfügen */
proc sql;
	create table Konten2 as select a.*, b.V_RMCUST_DECESIND as V_RMCUST_DECESIND2,
				b.V_CUST_UNDER_CUSTODIAN_FLG as V_CUST_UNDER_CUSTODIAN_FLG2 from
	Konten2 as a
	left join
	Cust as b
	on input(a.CIN2,14.) = input(b.V_RMCUST_CUSTNUMB,14.);
quit;

/* Informationen pro Kundenverbindung aufbereiten und anfügen */
proc sql;
	create table KV1 as
	select KV_ID, count(*) as KV_Acc, sum(Kontosaldo) as KV_Saldo,
			sum(Kapital) as KV_Kapital, sum(Kosten) as KV_Kosten,
			sum(Zinsen) as KV_Zinsen,
			max(D_CLE_LAST_PAYMENT_DATE) as KV_lastpay format date9.
	from Konten2
	group by KV_ID;
quit;

proc sql;
	create table Konten2 as
	select * from
	Konten2 as a
	left join
	KV1 as b
	on a.KV_ID=b.KV_ID;
quit;

/* stille Vergleiche werden weiter unten (ab Z. 347) analysiert */

/* Reputationsrisiko: Kundenalter */
data aus1;
set Konten2;
Grund = "Kundenalter";
if Alter > 79;
if KV_lastpay lt "01JUL2025"d;
if Buchwert = 0;
if State ne "";
run;

/* nur noch Zinsen */
data aus2;
set Konten2;
Grund = "Zinsen";
if KV_Kapital = 0;
if KV_Kosten = 0;
if KV_Zinsen > 0;
if State ne "";
if Buchwert = 0;
if KV_lastpay lt "01JUL2025"d;
run;

/* settled Kunden */
data aus3;
set Konten2;
Grund = "settled";
if Settled_kn1='ja' or Settled_kn2='ja';
if State ne "";
if Buchwert = 0;
if KV_lastpay lt "01JUL2025"d;
run;

/* Fraud */
data aus4;
set Konten2;
Grund = "Fraud";
if State in ("E38" "E39");
if Buchwert = 0;
if KV_lastpay lt "01JUL2025"d;
run;

/* Compliance */
data aus5;
set Konten2;
Grund = "Compliance";
if State in ("E32");
if Buchwert = 0;
if KV_lastpay lt "01JUL2025"d;
run;

/* Betreuung */
data aus6;
set Konten2;
Grund = "Betreuung";
if V_CUST_UNDER_CUSTODIAN_FLG = "Y" and V_CUST_UNDER_CUSTODIAN_FLG2 ne "N";
if Buchwert = 0;
if KV_lastpay lt "01JUL2025"d;
run;

/* falsch tituliert */
data aus7;
set Konten2;
Grund = "wrong Title";
if State in ("B33" "B34" "E98");
if Buchwert = 0;
if KV_lastpay lt "01JUL2025"d;
run;

/* Recall */
data aus8;
set Konten2;
Grund = "Recall";
if State in ("W25" "W26");
if Buchwert = 0;
if KV_lastpay lt "01JUL2025"d;
run;

/* FordKto */
data aus9;
set Konten2;
Grund = "FordKto";
if TTCC_DATE - OPEN_DATE lt 30;
if State ne "";
if Exclude_Final lt 201;
if Buchwert = 0;
if KV_lastpay lt "01JUL2025"d;
run;

/* Unterlagen fehlen */
data aus10;
set Konten2;
Grund = "Unterlagen";
if OPEN_DATE lt "01JAN2010"d;
if State ne "";
if CARD_NBR ne "";
if Buchwert = 0;
if KV_lastpay lt "01JUL2025"d;
run;

/* Datenzusammenfügen und exportieren */
data aus_all;
set aus1
	aus2
	aus3
	aus4
	aus5
	aus6
	aus7
	aus8
	aus9
	aus10;
if State ne "";
run;
/*
PROC EXPORT DATA= aus_all
	OUTFILE= "/home/ldap/&sysuserid./grpfpu/LAUBINKA/Data/Ausbuchungspotenziale_072026.xlsx"
	DBMS=XLSX REPLACE;
	newfile=Y;
RUN;
*/
