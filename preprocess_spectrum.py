import sqlite3
import pandas as pd
import numpy as np
import json
import os
from datetime import datetime

def build_expanded_spectral_data():
    db_candidates = [
        "MoneyBot_Backup_2026-08-15.db",
        "MoneyBot_Local.db",
        "../MoneyBot_Local.db"
    ]
    db_path = None
    for cand in db_candidates:
        if os.path.exists(cand):
            db_path = cand
            break
            
    if not db_path:
        raise FileNotFoundError("Database file not found!")
        
    print(f"Loading data from database: {db_path}")
    conn = sqlite3.connect(db_path)
    
    # 1. Extract raw data
    df_binance = pd.read_sql("SELECT Data_Hora, BTCBRL, ETHBRL, SOLBRL, BNBBRL, LINKBRL, ADABRL, USDTBRL FROM Historico_binance WHERE Data_Hora >= '2026-01-01' ORDER BY Data_Hora ASC", conn)
    df_rapido = pd.read_sql("SELECT Data_Hora, USD_BRL, EUR_BRL, IBOV_Pts, EWZ_Bolsa, SP500_Pts, QQQ_Tech, WTI_Oil FROM Historico_rapido WHERE Data_Hora >= '2026-01-01' ORDER BY Data_Hora ASC", conn)
    df_macro = pd.read_sql("SELECT Data as Data_Hora, Petroleo_Brent, Ouro_USD, VIX_Index, Treasury_10Y, DXY_Index, Copper_Index FROM Historico_macro WHERE Data >= '2026-01-01' ORDER BY Data ASC", conn)
    conn.close()
    
    # Clean datetime
    for df in [df_binance, df_rapido, df_macro]:
        df['Data_Hora'] = pd.to_datetime(df['Data_Hora'], errors='coerce')
        df.dropna(subset=['Data_Hora'], inplace=True)
        df.set_index('Data_Hora', inplace=True)
        df.sort_index(inplace=True)
        
    # Standardize column naming
    rename_map = {
        'BTCBRL': 'BTC', 'ETHBRL': 'ETH', 'SOLBRL': 'SOL', 'BNBBRL': 'BNB', 'LINKBRL': 'LINK', 'ADABRL': 'ADA', 'USDTBRL': 'USDT',
        'USD_BRL': 'USD/BRL', 'EUR_BRL': 'EUR/BRL', 'IBOV_Pts': 'IBOV', 'EWZ_Bolsa': 'EWZ', 'SP500_Pts': 'SP500', 'QQQ_Tech': 'QQQ', 'WTI_Oil': 'WTI',
        'Petroleo_Brent': 'BRENT', 'Ouro_USD': 'GOLD', 'VIX_Index': 'VIX', 'Treasury_10Y': 'US10Y', 'DXY_Index': 'DXY', 'Copper_Index': 'COPPER'
    }
    df_binance.rename(columns=rename_map, inplace=True)
    df_rapido.rename(columns=rename_map, inplace=True)
    df_macro.rename(columns=rename_map, inplace=True)
    
    # Merge and resample to 1-hour uniform continuous grid
    df_all = pd.concat([df_binance, df_rapido, df_macro], axis=1)
    df_hourly = df_all.resample('1h').last().ffill().bfill()
    
    # 2. Add Synthetic and Cross-Asset Indicators for richer topological interactions
    df_hourly['ETH/BTC'] = df_hourly['ETH'] / (df_hourly['BTC'] + 1e-9)
    df_hourly['SOL/BTC'] = df_hourly['SOL'] / (df_hourly['BTC'] + 1e-9)
    df_hourly['GOLD_BRL'] = df_hourly['GOLD'] * df_hourly['USD/BRL']
    df_hourly['BRENT_BRL'] = df_hourly['BRENT'] * df_hourly['USD/BRL']
    df_hourly['EUR/USD'] = df_hourly['EUR/BRL'] / (df_hourly['USD/BRL'] + 1e-9)
    df_hourly['TECH_RATIO'] = df_hourly['QQQ'] / (df_hourly['SP500'] + 1e-9)
    df_hourly['EWZ/SP500'] = df_hourly['EWZ'] / (df_hourly['SP500'] + 1e-9)
    
    # Complete Asset Universe (25 Assets across 4 core sectors)
    asset_meta = {
        # Crypto Cluster (Gold/Orange)
        'BTC': {'name': 'Bitcoin', 'category': 'crypto', 'color': '#F59E0B', 'desc': 'Digital Gold / Liquidez Cripto Global'},
        'ETH': {'name': 'Ethereum', 'category': 'crypto', 'color': '#F59E0B', 'desc': 'Smart Contracts Layer 1'},
        'SOL': {'name': 'Solana', 'category': 'crypto', 'color': '#F59E0B', 'desc': 'High-Throughput L1 Ecosystem'},
        'BNB': {'name': 'Binance Coin', 'category': 'crypto', 'color': '#F59E0B', 'desc': 'Exchange Utility & BSC Token'},
        'LINK': {'name': 'Chainlink', 'category': 'crypto', 'color': '#F59E0B', 'desc': 'Oracle Middleware Network'},
        'ADA': {'name': 'Cardano', 'category': 'crypto', 'color': '#F59E0B', 'desc': 'Proof-of-Stake Layer 1'},
        'USDT': {'name': 'Tether USD', 'category': 'crypto', 'color': '#F59E0B', 'desc': 'Stablecoin Spot BRL'},
        'ETH/BTC': {'name': 'Par ETH/BTC', 'category': 'crypto', 'color': '#F59E0B', 'desc': 'Força Relativa Ethereum vs Bitcoin'},
        'SOL/BTC': {'name': 'Par SOL/BTC', 'category': 'crypto', 'color': '#F59E0B', 'desc': 'Força Relativa Solana vs Bitcoin'},
        
        # TradFi / Equities Cluster (Cyan)
        'IBOV': {'name': 'Ibovespa', 'category': 'tradfi', 'color': '#06B6D4', 'desc': 'Índice de Ações B3 Brasil'},
        'EWZ': {'name': 'MSCI Brazil ETF', 'category': 'tradfi', 'color': '#06B6D4', 'desc': 'Exposição Internacional Brasil em Dólar'},
        'SP500': {'name': 'S&P 500 Index', 'category': 'tradfi', 'color': '#06B6D4', 'desc': 'Benchmark Ações Globais EUA'},
        'QQQ': {'name': 'Nasdaq 100 ETF', 'category': 'tradfi', 'color': '#06B6D4', 'desc': 'Big Techs e Inovação Global'},
        'TECH_RATIO': {'name': 'Nasdaq / SP500', 'category': 'tradfi', 'color': '#06B6D4', 'desc': 'Liderança Tecnológica Relativa'},
        'EWZ/SP500': {'name': 'Brasil / EUA Relativo', 'category': 'tradfi', 'color': '#06B6D4', 'desc': 'Fluxo de Capital Emergente vs Desenvolvido'},
        
        # FX / Currencies Cluster (Emerald)
        'USD/BRL': {'name': 'Dólar Spot BRL', 'category': 'fx', 'color': '#10B981', 'desc': 'Taxa de Câmbio Comercial USD/BRL'},
        'EUR/BRL': {'name': 'Euro Spot BRL', 'category': 'fx', 'color': '#10B981', 'desc': 'Taxa de Câmbio Spot EUR/BRL'},
        'DXY': {'name': 'Dollar Index DXY', 'category': 'fx', 'color': '#10B981', 'desc': 'Força Global da Moeda Americana'},
        'EUR/USD': {'name': 'Par EUR/USD', 'category': 'fx', 'color': '#10B981', 'desc': 'Par Cambial Mais Líquido do Mundo'},
        
        # Macro / Commodities / Rates Cluster (Magenta / Purple)
        'US10Y': {'name': 'US Treasury 10Y', 'category': 'macro', 'color': '#EC4899', 'desc': 'Taxa Livre de Risco / Yield Soberano EUA'},
        'VIX': {'name': 'CBOE VIX', 'category': 'macro', 'color': '#EC4899', 'desc': 'Índice do Medo / Volatilidade Implícita'},
        'GOLD': {'name': 'Ouro Spot USD', 'category': 'macro', 'color': '#EC4899', 'desc': 'Ouro Onça-Troy / Reserva Global'},
        'GOLD_BRL': {'name': 'Ouro em Reais (BRL)', 'category': 'macro', 'color': '#EC4899', 'desc': 'Ouro precificado em moeda brasileira'},
        'BRENT': {'name': 'Petróleo Brent', 'category': 'macro', 'color': '#EC4899', 'desc': 'Referência Energética Mundial'},
        'WTI': {'name': 'Petróleo WTI', 'category': 'macro', 'color': '#EC4899', 'desc': 'Petróleo dos Estados Unidos'},
        'COPPER': {'name': 'Cobre Spot', 'category': 'macro', 'color': '#EC4899', 'desc': 'Dr. Cobre / Termômetro da Indústria'}
    }
    
    asset_keys = [k for k in asset_meta.keys() if k in df_hourly.columns]
    print(f"Total Active Asset Universe: {len(asset_keys)} assets")
    df_hourly = df_hourly[asset_keys]
    
    # 3. Frequency Band Returns Decomposition
    # Band 1: Ultra-High Frequency (1h returns)
    r_band1 = np.log(df_hourly / df_hourly.shift(1)).dropna()
    
    # Band 2: Intraday Session (6h rolling returns)
    r_band2 = np.log(df_hourly / df_hourly.shift(6)).dropna()
    
    # Band 3: Daily / Swing (24h rolling returns)
    r_band3 = np.log(df_hourly / df_hourly.shift(24)).dropna()
    
    # Band 4: Macro / Secular (120h / 5d rolling returns)
    r_band4 = np.log(df_hourly / df_hourly.shift(120)).dropna()
    
    bands_dict = {
        'ultra_high': {'name': 'Ultra-Alta / Ruído (15m - 1h)', 'data': r_band1, 'freq_hz': '100 Hz', 'band_id': 1},
        'intraday': {'name': 'Intraday / Sessão (4h - 8h)', 'data': r_band2, 'freq_hz': '25 Hz', 'band_id': 2},
        'daily': {'name': 'Swing / Diário (24h)', 'data': r_band3, 'freq_hz': '5 Hz', 'band_id': 3},
        'macro': {'name': 'Macro / Secular (3d - 7d)', 'data': r_band4, 'freq_hz': '1 Hz', 'band_id': 4}
    }
    
    epochs_dict = {
        '2026-ALL': ('2026-01-01', '2026-08-31', 'Ano Completo 2026 (Agregado)'),
        '2026-01': ('2026-01-01', '2026-01-31', 'Janeiro 2026 (Início do Ano)'),
        '2026-02': ('2026-02-01', '2026-02-28', 'Fevereiro 2026 (Transição de Volatilidade)'),
        '2026-03': ('2026-03-01', '2026-03-31', 'Março 2026 (Ajuste de Política Monetária)'),
        '2026-04': ('2026-04-01', '2026-04-30', 'Abril 2026 (Halving & Rebalanceamento)'),
        '2026-05': ('2026-05-01', '2026-05-31', 'Maio 2026 (Rompimento Secular)'),
        '2026-06': ('2026-06-01', '2026-06-30', 'Junho 2026 (Migração & Estabilidade)'),
        '2026-07': ('2026-07-01', '2026-07-31', 'Julho 2026 (Consolidação de Verão)'),
        '2026-08': ('2026-08-01', '2026-08-31', 'Agosto 2026 (Ciclo Corrente)')
    }
    
    # Helper: Kruskal's MST
    def compute_mst(corr_mat, assets):
        n = len(assets)
        dist_mat = np.sqrt(np.maximum(0, 2.0 * (1.0 - corr_mat)))
        
        edges = []
        for i in range(n):
            for j in range(i + 1, n):
                edges.append((dist_mat[i, j], corr_mat[i, j], i, j))
                
        edges.sort(key=lambda x: x[0])
        
        parent = list(range(n))
        def find(u):
            if parent[u] == u: return u
            parent[u] = find(parent[u])
            return parent[u]
            
        def union(u, v):
            root_u, root_v = find(u), find(v)
            if root_u != root_v:
                parent[root_u] = root_v
                return True
            return False
            
        mst_edges = []
        for dist, corr, u, v in edges:
            if union(u, v):
                mst_edges.append({
                    'source': assets[u],
                    'target': assets[v],
                    'weight': round(float(corr), 4),
                    'distance': round(float(dist), 4),
                    'is_mst': True
                })
                if len(mst_edges) == n - 1:
                    break
        return mst_edges

    # Helper: Betweenness Centrality on graph
    def compute_betweenness(adj_matrix):
        n = len(adj_matrix)
        cb = {i: 0.0 for i in range(n)}
        for s in range(n):
            stack = []
            pred = {w: [] for w in range(n)}
            sigma = {w: 0.0 for w in range(n)}
            sigma[s] = 1.0
            dist = {w: -1 for w in range(n)}
            dist[s] = 0
            queue = [s]
            
            while queue:
                v = queue.pop(0)
                stack.append(v)
                for w in range(n):
                    if adj_matrix[v][w] > 0:
                        if dist[w] < 0:
                            dist[w] = dist[v] + 1
                            queue.append(w)
                        if dist[w] == dist[v] + 1:
                            sigma[w] += sigma[v]
                            pred[w].append(v)
                            
            delta = {w: 0.0 for w in range(n)}
            while stack:
                w = stack.pop()
                for v in pred[w]:
                    delta[v] += (sigma[v] / (sigma[w] + 1e-9)) * (1.0 + delta[w])
                if w != s:
                    cb[w] += delta[w]
                    
        norm = max(1.0, (n - 1) * (n - 2))
        return {k: round(v / norm, 4) for k, v in cb.items()}

    output_tensor = {
        'metadata': {
            'generated_at': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'total_assets': len(asset_keys),
            'assets': {k: asset_meta[k] for k in asset_keys},
            'bands': {k: {'name': v['name'], 'freq_hz': v['freq_hz'], 'id': v['band_id']} for k, v in bands_dict.items()},
            'epochs': {k: {'name': v[2], 'start': v[0], 'end': v[1]} for k, v in epochs_dict.items()}
        },
        'data': {}
    }

    print("Computing Multi-Frequency Topologies for all 25 assets...")
    
    for epoch_key, (start_d, end_d, epoch_label) in epochs_dict.items():
        output_tensor['data'][epoch_key] = {}
        
        for band_key, band_info in bands_dict.items():
            r_data = band_info['data']
            mask = (r_data.index >= start_d) & (r_data.index <= end_d + ' 23:59:59')
            sub_r = r_data.loc[mask]
            
            if len(sub_r) < 15:
                sub_r = r_data
                
            corr_df = sub_r.corr().fillna(0.0)
            corr_mat = corr_df.values
            
            # PCA & Absorption Ratio
            try:
                eigenvalues = np.linalg.eigvalsh(corr_mat)
                eigenvalues = np.sort(eigenvalues)[::-1]
                abs_ratio = float((eigenvalues[0] / np.sum(eigenvalues)) * 100.0)
            except Exception:
                abs_ratio = 35.0
                
            # MST Backbone
            mst_edges = compute_mst(corr_mat, asset_keys)
            
            # Significant Edges
            all_edges = []
            mst_pairs = set(tuple(sorted([e['source'], e['target']])) for e in mst_edges)
            adj_graph = np.zeros((len(asset_keys), len(asset_keys)))
            
            for i in range(len(asset_keys)):
                for j in range(i + 1, len(asset_keys)):
                    c_val = float(corr_mat[i, j])
                    d_val = float(np.sqrt(max(0, 2.0 * (1.0 - c_val))))
                    is_in_mst = tuple(sorted([asset_keys[i], asset_keys[j]])) in mst_pairs
                    
                    # Store all MST edges and correlations with |corr| >= 0.20
                    if is_in_mst or abs(c_val) >= 0.20:
                        adj_graph[i, j] = 1
                        adj_graph[j, i] = 1
                        all_edges.append({
                            'source': asset_keys[i],
                            'target': asset_keys[j],
                            'weight': round(c_val, 4),
                            'distance': round(d_val, 4),
                            'is_mst': is_in_mst,
                            'type': 'sync' if c_val >= 0 else 'hedge'
                        })
                        
            # Graph Centrality
            cb_scores = compute_betweenness(adj_graph)
            
            # Build Node list
            nodes = []
            for idx, a_key in enumerate(asset_keys):
                vol = float(sub_r[a_key].std() * np.sqrt(252 * (24 if band_key == 'ultra_high' else 1))) if len(sub_r) > 1 else 0.0
                ret = float(sub_r[a_key].mean() * len(sub_r))
                degree = int(np.sum(adj_graph[idx]))
                
                nodes.append({
                    'id': a_key,
                    'name': asset_meta[a_key]['name'],
                    'category': asset_meta[a_key]['category'],
                    'color': asset_meta[a_key]['color'],
                    'betweenness': cb_scores[idx],
                    'degree': degree,
                    'volatility': round(vol, 4),
                    'cum_return': round(ret * 100.0, 2),
                    'size': round(11 + (cb_scores[idx] * 26) + (degree * 1.0), 1)
                })
                
            # Dominant Hub
            dominant_hub = max(nodes, key=lambda n: n['betweenness'] * 2 + n['degree'])['id']
            triu_idx = np.triu_indices(len(asset_keys), k=1)
            mean_coherence = float(np.mean(np.abs(corr_mat[triu_idx])))
            
            # Top positive & negative pairs
            sorted_edges = sorted(all_edges, key=lambda e: e['weight'], reverse=True)
            top_sync = [{'pair': f"{e['source']} / {e['target']}", 'corr': e['weight']} for e in sorted_edges[:4] if e['weight'] > 0]
            top_hedge = [{'pair': f"{e['source']} / {e['target']}", 'corr': e['weight']} for e in sorted_edges[::-1][:4] if e['weight'] < 0]
            
            output_tensor['data'][epoch_key][band_key] = {
                'nodes': nodes,
                'edges': all_edges,
                'telemetry': {
                    'absorption_ratio_pc1': round(abs_ratio, 2),
                    'mean_coherence': round(mean_coherence, 3),
                    'dominant_hub': dominant_hub,
                    'edge_count': len(all_edges),
                    'mst_edge_count': len(mst_edges),
                    'top_sync_pairs': top_sync,
                    'top_hedge_pairs': top_hedge
                }
            }

    # 1. Write JSON
    os.makedirs("harmonicus", exist_ok=True)
    json_path = os.path.join("harmonicus", "network_spectrum_data.json")
    with open(json_path, 'w', encoding='utf-8') as f:
        json.dump(output_tensor, f, indent=2, ensure_ascii=False)
        
    # 2. Write data.js for 100% offline & local file:// instant loading without CORS issues
    js_path = os.path.join("harmonicus", "data.js")
    with open(js_path, 'w', encoding='utf-8') as f:
        f.write("window.HARMONICUS_DATA = ")
        json.dump(output_tensor, f, ensure_ascii=False)
        f.write(";\n")
        
    print(f"Generated {json_path} ({round(os.path.getsize(json_path)/1024, 1)} KB)")
    print(f"Generated {js_path} ({round(os.path.getsize(js_path)/1024, 1)} KB)")

if __name__ == '__main__':
    build_expanded_spectral_data()
