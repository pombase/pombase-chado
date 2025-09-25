#!/usr/bin/env python3
#
# /// script
# dependencies = [
#   "pandas", "matplotlib"
# ]
# ///

import sys

import pandas as pd
import matplotlib.pyplot as plt

type = sys.argv[1]
y_label = sys.argv[2]
file = sys.argv[3]
out = sys.argv[4]

df = pd.read_csv(file)

df['date'] = pd.to_datetime(df['date']).map(lambda dt: dt.strftime('%Y-%m'))

default_dpi=600
figsize=(8,5)
fig, ax = plt.subplots(dpi=default_dpi, figsize=figsize)

ax = df.plot(ax=ax, legend=False, kind='line', x='date', y=type + 's')

plt.subplots_adjust(bottom=0.18)
plt.grid(color='0.85')

ax.tick_params(axis='x', labelrotation = 45)

plt.xlabel('Date')
plt.ylabel(y_label)

plt.savefig(out)
