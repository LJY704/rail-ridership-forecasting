/* =============================================================
   KORAIL monthly ridership: 2024 holdout model comparison
   Train: 2017-01 to 2023-12 (84 months)
   Test : 2024-01 to 2024-12 (12 months)
   Models: SARIMA(1,1,1)(0,1,1)[12], Winters ESM, Seasonal naive
   Metrics: MAE, RMSE, MAPE (in original passenger-count units)
   IMPORTANT: SAS execution and convergence still need verification.
   ============================================================= */

%let source_file=/home/u63579110/원본 데이터/졸업논문 데이터1.xlsx;
options validvarname=any;

/* 1. Import and discard spreadsheet's trailing blank rows. */
proc import datafile="&source_file" out=work.rail_raw dbms=xlsx replace;
  getnames=yes;
run;

data work.rail_all;
  set work.rail_raw;
  passenger_count=input(compress(strip(vvalue(Passenger)),','),best32.);
  if missing(passenger_count) then delete;
  if passenger_count<=0 then do;
    put 'ERROR: Non-positive passenger_count in input row ' _n_;
    stop;
  end;
  t+1;
  date=intnx('month','01JAN2017'd,t-1,'b');
  format date yymmn7.;
  logpassenger=log(passenger_count);
  keep t date passenger_count logpassenger;
run;

proc sql noprint;
  select count(*) into :n_months trimmed from work.rail_all;
quit;
%macro check_input;
  %if &n_months ne 96 %then %do;
    %put ERROR: Expected 96 valid months, found &n_months.. Stop and inspect input.;
    %abort cancel;
  %end;
%mend;
%check_input;

/* 2. Time-ordered split: no information from 2024 is used for fitting. */
data work.rail_train work.rail_test;
  set work.rail_all;
  if date<'01JAN2024'd then output work.rail_train;
  else if '01JAN2024'd<=date<='01DEC2024'd then output work.rail_test;
run;

proc sql;
  title 'Data split validation';
  select 'Train' as subset, count(*) as n from work.rail_train
  union all
  select 'Test' as subset, count(*) as n from work.rail_test;
quit;
title;

/* 3. SARIMA fitted on TRAIN only. Forecast is on log scale.
   exp(log forecast) returns a median-scale point forecast, not a
   bias-corrected conditional mean. Treat this consistently when comparing. */
ods graphics on;
proc arima data=work.rail_train plots=all;
  identify var=logpassenger(1,12) nlag=24;
  estimate p=1 q=(1)(12) method=ml;
  forecast lead=12 id=date interval=month out=work.sarima_raw;
run;
quit;

data work.pred_sarima;
  set work.sarima_raw;
  where '01JAN2024'd<=date<='01DEC2024'd;
  length model $24;
  model='SARIMA';
  predicted=exp(forecast);
  keep date model predicted;
run;

/* 4. Winters exponential smoothing fitted on TRAIN only.
   OUTFOR contains ACTUAL and PREDICT for the forecast variable. */
proc esm data=work.rail_train outfor=work.winters_raw lead=12;
  id date interval=month;
  forecast passenger_count / model=winters;
run;

data work.pred_winters;
  set work.winters_raw;
  where '01JAN2024'd<=date<='01DEC2024'd;
  length model $24;
  model='Winters';
  predicted=predict;
  keep date model predicted;
run;

/* 5. Seasonal naive: predict 2024 month with same month in 2023. */
data work.pred_naive;
  set work.rail_train;
  where '01JAN2023'd<=date<='01DEC2023'd;
  date=intnx('year',date,1,'same');
  length model $24;
  model='Seasonal naive';
  predicted=passenger_count;
  keep date model predicted;
run;

/* 6. Combine forecasts and match to ACTUAL 2024 observations. */
data work.pred_all;
  set work.pred_sarima work.pred_winters work.pred_naive;
run;

proc sql;
  create table work.validation as
  select p.model, p.date format=yymmn7.,
         a.passenger_count as actual, p.predicted
  from work.pred_all as p
  left join work.rail_test as a on p.date=a.date
  order by p.model, p.date;
quit;

data work.validation;
  set work.validation;
  error=actual-predicted;
  abs_error=abs(error);
  sq_error=error**2;
  if actual>0 then ape=100*abs_error/actual;
  else ape=.;
run;

/* 7. Evaluation in passenger-count units.
   Require 12 nonmissing predictions before considering a model valid. */
proc sql;
  create table work.model_metrics0 as
  select model, count(*) as forecast_rows,
         count(predicted) as valid_predictions,
         mean(abs_error) as MAE format=comma18.2,
         sqrt(mean(sq_error)) as RMSE format=comma18.2,
         mean(ape) as MAPE format=8.3
  from work.validation
  group by model;
quit;

data work.model_metrics;
  set work.model_metrics0;
  length evaluation_status $35;
  if forecast_rows=12 and valid_predictions=12 then evaluation_status='OK';
  else evaluation_status='CHECK: missing forecast(s)';
run;

proc print data=work.model_metrics noobs label;
  title '2024 holdout: model comparison (MAE/RMSE passengers, MAPE percent)';
run;

proc print data=work.validation noobs;
  var model date actual predicted error abs_error ape;
  format actual predicted error abs_error comma18.0 ape 8.2;
  title '2024 monthly actual versus predicted';
run;

/* 8. Comparison chart (one series per model). */
data work.plot_long;
  set work.validation;
  length series $30;
  series=model;
  value=predicted;
  output;
  if model='SARIMA' then do;
    series='Actual 2024'; value=actual; output;
  end;
  keep date series value;
run;
proc sgplot data=work.plot_long;
  series x=date y=value / group=series markers;
  xaxis label='2024 month' values=('01JAN2024'd to '01DEC2024'd by month)
        valuesformat=monyy7.;
  yaxis label='Monthly boardings';
  title '2024 holdout: observed and predicted ridership';
run;
ods graphics off;
title;

/* INTERPRETATION CHECKLIST:
   - Check SAS LOG for errors and ARIMA convergence warnings.
   - Compare metrics only for models with 12 valid forecasts.
   - Examine SARIMA residual diagnostics before selecting final model.
   - Keep COVID-era values in the primary analysis; they are real demand shocks.
   - After selecting a model, refit on all 96 months for 2025-2026 forecast.
*/
