import sqlite3
import json
import pandas as pd
import os

db_path = '../MoneyBot_Local.db'
if not os.path.exists(db_path):
    print("DB not found!")
    exit(1)

conn = sqlite3.connect(db_path)
query = "SELECT Data_Hora, USD_BRL FROM Historico_rapido WHERE USD_BRL IS NOT NULL ORDER BY Data_Hora ASC"
df = pd.read_sql_query(query, conn)
conn.close()

df = df.tail(10000).copy()

df['MA'] = df['USD_BRL'].rolling(window=20).mean()
df['STD'] = df['USD_BRL'].rolling(window=20).std()
df['Upper_Risk'] = df['MA'] + (df['STD'] * 2)
df['Lower_Risk'] = df['MA'] - (df['STD'] * 2)

df.bfill(inplace=True)

data = {
    'timestamps': df['Data_Hora'].tolist(),
    'prices': df['USD_BRL'].tolist(),
    'upper_risk': df['Upper_Risk'].tolist(),
    'lower_risk': df['Lower_Risk'].tolist()
}

with open('data.js', 'w') as f:
    f.write('const rawData = ' + json.dumps(data) + ';')

print("Data exported successfully to data.js")
