"""KORAIL monthly rail boardings: four portfolio charts.
Run: pip install pandas openpyxl matplotlib numpy
     python rail_portfolio_charts.py
Run from anywhere; data/rail_original.xlsx is included in the repository.
Forecast values transcribed from SAS WORK.FINAL_FORECAST screenshot.
"""
from pathlib import Path
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter

ROOT = Path(__file__).resolve().parent
EXCEL = ROOT.parent / 'data' / 'rail_original.xlsx'
OUT = ROOT.parent / 'figures'
OUT.mkdir(exist_ok=True)
plt.rcParams.update({'font.family': ['DejaVu Sans'], 'axes.unicode_minus': False,
                     'figure.dpi': 130, 'savefig.dpi': 200, 'axes.spines.top': False,
                     'axes.spines.right': False, 'font.size': 10})

raw = pd.read_excel(EXCEL)
values = pd.to_numeric(raw['Passenger'].astype(str).str.replace(',', '', regex=False), errors='coerce').dropna()
if len(values) != 96:
    raise ValueError(f'Expected 96 valid months, found {len(values)}')
actual = pd.DataFrame({'date': pd.date_range('2017-01-01', periods=96, freq='MS'), 'passengers': values.to_numpy()})

forecast_values = [
 61906614,56489049,66209683,66462010,69020367,65599241,
 64344613,61894200,63673991,67251739,67550303,64844581,
 61451515,56073523,65722354,65972524,68511726,65115516,
 63869847,61437234,63203595,66754606,67050655,64364650]
forecast = pd.DataFrame({'date': pd.date_range('2025-01-01', periods=24, freq='MS'), 'passengers': forecast_values})
forecast['year'] = forecast.date.dt.year
forecast['month'] = forecast.date.dt.month
forecast.to_csv(ROOT.parent / 'data' / 'winters_forecast_2025_2026.csv', index=False, encoding='utf-8-sig')
actual.to_csv(ROOT.parent / 'data' / 'rail_actual_2017_2024.csv', index=False, encoding='utf-8-sig')

# Chart 1: Historical series and COVID period
fig, ax = plt.subplots(figsize=(12, 5.3))
ax.plot(actual.date, actual.passengers / 1e6, lw=2, color='#245a85', label='Observed boardings')
ax.axvspan(pd.Timestamp('2020-01-01'), pd.Timestamp('2022-02-01'), color='#e9a8a1', alpha=.23, label='COVID impact period (illustrative)')
ax.set(title='Monthly rail ridership | 2017–2024', ylabel='Million boardings', xlabel='')
ax.grid(alpha=.2); ax.legend(frameon=False, loc='lower left')
fig.tight_layout(); fig.savefig(OUT / '01_historical_trend.png'); plt.close(fig)

# Chart 2: Same-month baseline comparisons for shock severity, no causal claim
baseline = actual[actual.date.dt.year.isin([2017, 2018, 2019])].assign(month=lambda d: d.date.dt.month).groupby('month').passengers.mean()
covid = actual[actual.date.dt.year == 2020].copy()
covid['month'] = covid.date.dt.month
covid['pct_vs_baseline'] = (covid.passengers / covid.month.map(baseline) - 1) * 100
fig, ax = plt.subplots(figsize=(11, 5.3))
colors = ['#bc594e' if v < 0 else '#388776' for v in covid.pct_vs_baseline]
ax.bar(covid.month, covid.pct_vs_baseline, color=colors, width=.7)
ax.axhline(0, color='#666', lw=.8)
ax.set(xticks=range(1,13), xlabel='2020 month', ylabel='Change (%)',
       title='2020 ridership vs. 2017–2019 same-month average')
ax.grid(axis='y', alpha=.2)
fig.text(.12,.01,'Descriptive comparison; not a causal estimate of COVID-19 impact.',fontsize=9,color='#555')
fig.tight_layout(rect=[0,.04,1,1]); fig.savefig(OUT / '02_2020_vs_baseline.png'); plt.close(fig)

# Chart 3: Previously computed holdout metrics (SAS program 2)
models = ['Winters', 'Seasonal naïve', 'SARIMA']
mae = [1691282,1815355,2000076]
rmse = [1888397,2383976,2187814]
mape = [2.556,2.768,3.082]
fig, axes = plt.subplots(1,3,figsize=(13.5,4.6))
for ax, vals, title, unit in zip(axes,[mae,rmse,mape],['MAE','RMSE','MAPE'],['million passengers','million passengers','%']):
    plot_vals = [v/1e6 for v in vals] if title!='MAPE' else vals
    bars = ax.barh(models[::-1], plot_vals[::-1], color=['#8a9eac','#8a9eac','#247c73'][::-1])
    ax.set(title=title, xlabel=unit)
    ax.set_xlim(0,max(plot_vals)*1.23)
    for bar,v in zip(bars,plot_vals[::-1]):
        ax.text(bar.get_width()+max(plot_vals)*.025,bar.get_y()+bar.get_height()/2,f'{v:.3f}',va='center',fontsize=9)
    ax.grid(axis='x',alpha=.16)
fig.suptitle('2024 holdout forecast accuracy | lower is better',fontsize=15,y=1.03)
fig.tight_layout(); fig.savefig(OUT / '03_model_comparison.png',bbox_inches='tight'); plt.close(fig)

# Chart 4: Forecast separated from observed series
fig, ax = plt.subplots(figsize=(12,5.4))
ax.plot(actual.date,actual.passengers/1e6,color='#245a85',lw=2,label='Observed (2017–2024)')
ax.plot(forecast.date,forecast.passengers/1e6,color='#d07b34',lw=2.2,marker='o',ms=3,label='Winters forecast (2025–2026)')
ax.axvline(pd.Timestamp('2025-01-01'),color='#777',ls='--',lw=1)
ax.axvspan(pd.Timestamp('2025-01-01'),pd.Timestamp('2026-12-31'),alpha=.07,color='#d07b34')
ax.set(title='Monthly rail ridership | observed and 24-month forecast',ylabel='Million boardings',xlabel='')
ax.grid(alpha=.2); ax.legend(frameon=False,loc='lower left')
fig.tight_layout(); fig.savefig(OUT / '04_final_winters_forecast.png'); plt.close(fig)

print('Saved 4 PNG charts to:',OUT)
print('Forecast annual totals:',forecast.groupby('year').passengers.sum().to_dict())
print('2020 vs same-month baseline min:',covid.pct_vs_baseline.min())
