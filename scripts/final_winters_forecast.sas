/* ================================================================
   KORAIL monthly passenger demand: final Winters forecast
   Training: Jan 2017 - Dec 2024 (96 monthly observations)
   Forecast: Jan 2025 - Dec 2026 (24 months)
   Forecast origin: 2024-12 (not a retrospective actual-value analysis)
   SAS Studio / SAS 9.4, SAS/ETS PROC ESM required
   ================================================================ */

%let source_file=/home/u63579110/원본 데이터/졸업논문 데이터1.xlsx;
options validvarname=any;

/* 1. Read the original spreadsheet. Drop trailing blank rows. */
proc import datafile="&source_file" out=work.rail_raw dbms=xlsx replace;
  getnames=yes;
run;

data work.rail_all;
  set work.rail_raw;
  passenger_count=input(compress(strip(vvalue(Passenger)),','),best32.);
  if missing(passenger_count) then delete;
  if passenger_count<=0 then do;
    put 'ERROR: Non-positive passenger count at Excel data row ' _n_;
    stop;
  end;
  t+1;
  date=intnx('month','01JAN2017'd,t-1,'b');
  format date yymmn7.;
  keep t date passenger_count;
run;

/* Stop if the monthly series does not contain exactly 96 observations. */
proc sql noprint;
  select count(*) into :n_months trimmed from work.rail_all;
quit;
%macro validate;
  %if &n_months ne 96 %then %do;
    %put ERROR: Expected 96 monthly observations but found &n_months..;
    %abort cancel;
  %end;
%mend;
%validate;

proc sql;
  title 'Input check: 2017-2024, 96 monthly observations';
  select count(*) as n_months,
         min(date) as first_month format=yymmn7.,
         max(date) as last_month format=yymmn7.,
         min(passenger_count) as min_boardings format=comma18.,
         max(passenger_count) as max_boardings format=comma18.
  from work.rail_all;
quit;
title;

/* 2. Fit Winters exponential smoothing on all 96 months.
      Keep COVID-era observations: they are genuine demand shocks.
      PROC ESM outputs fitted/forecast rows in OUTFOR. */
ods graphics on;
proc esm data=work.rail_all outfor=work.winters_all lead=24;
  id date interval=month;
  forecast passenger_count / model=winters;
run;

/* 3. Extract the 24 out-of-sample monthly forecasts.
      PREDICT is in the original unit: passenger boardings. */
data work.final_forecast;
  set work.winters_all;
  where '01JAN2025'd <= date <= '01DEC2026'd;
  year=year(date);
  month=month(date);
  forecast_passengers=predict;
  format date yymmn7. forecast_passengers comma18.;
  keep date year month forecast_passengers;
run;

proc sql noprint;
  select count(*), sum(missing(forecast_passengers))
  into :forecast_rows trimmed, :missing_forecasts trimmed
  from work.final_forecast;
quit;
%put NOTE: Expected 24 forecasts; found &forecast_rows.;
%put NOTE: Missing forecast values: &missing_forecasts.;

proc print data=work.final_forecast noobs label;
  label date='Forecast month'
        year='Year'
        month='Month'
        forecast_passengers='Predicted passenger boardings';
  title 'Winters: monthly forecasts for 2025-2026 (24 months)';
run;
title;

/* 4. Annual totals of the monthly forecasts. */
proc sql;
  create table work.annual_forecast as
  select year,
         sum(forecast_passengers) as annual_forecast format=comma20.,
         mean(forecast_passengers) as average_monthly_forecast format=comma18.
  from work.final_forecast
  group by year
  order by year;
quit;
proc print data=work.annual_forecast noobs label;
  label annual_forecast='Annual sum of monthly forecasts'
        average_monthly_forecast='Mean monthly forecast';
  title 'Winters: annual summary of 2025-2026 forecasts';
run;
title;

/* 5. Chart: observed values and forecast values. */
data work.plot_actual;
  set work.rail_all;
  actual=passenger_count;
  keep date actual;
run;
proc sort data=work.plot_actual; by date; run;
proc sort data=work.final_forecast; by date; run;
data work.plot_final;
  merge work.plot_actual(in=a) work.final_forecast(keep=date forecast_passengers);
  by date;
run;

proc sgplot data=work.plot_final;
  series x=date y=actual / lineattrs=(color=cx336699 thickness=2)
      legendlabel='Observed (2017-2024)';
  series x=date y=forecast_passengers / lineattrs=(color=cxD97706 thickness=2 pattern=shortdash)
      legendlabel='Winters forecast (2025-2026)';
  refline '01JAN2025'd / axis=x lineattrs=(pattern=dot color=gray);
  xaxis label='Month' interval=year;
  yaxis label='Monthly passenger boardings' grid;
  keylegend / location=outside position=bottom;
  title 'KORAIL ridership: observed and Winters forecast';
run;


/* 6. Optional CSV export to the SAS server's temporary WORK folder.
      Use the SAS Studio Files panel to download this file if desired. */
%let output_csv=%sysfunc(pathname(work))/rail_winters_forecast_2025_2026.csv;
proc export data=work.final_forecast outfile="&output_csv"
  dbms=csv replace;
run;
%put NOTE: Forecast CSV saved to &output_csv.;

ods graphics off;
/* Interpretation: These are projections made using data through 2024-12.
   The 2024 holdout result supports model selection, not guaranteed accuracy
   for 2025-2026. Check PROC ESM notes for any fitting issues. */
